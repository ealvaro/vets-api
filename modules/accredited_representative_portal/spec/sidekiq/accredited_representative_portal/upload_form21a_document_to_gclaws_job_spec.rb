# frozen_string_literal: true

require 'rails_helper'
require_relative '../../spec_helper'

RSpec.describe AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob, type: :job do
  let(:form21a_attachment_guid) { SecureRandom.uuid }
  let(:application_id) { '12345' }
  let(:document_type) { 1 }
  let(:original_file_name) { 'test_document.pdf' }
  let(:content_type) { 'application/pdf' }
  let(:document_upload_url) { 'https://example.com/gclaws/document-upload' }

  let(:form21a_attachment) do
    create(
      :form_attachment,
      guid: form21a_attachment_guid,
      type: 'AccreditedRepresentativePortal::Form21aAttachment'
    )
  end

  # Mock file needs `delete` for FormAttachment's before_destroy callback
  let(:mock_file) { double('file', read: 'file contents', delete: true) }

  before do
    allow(Settings.ogc.form21a_service_url)
      .to receive_messages(document_upload_url:, api_key: 'test_api_key')
  end

  def multipart_request?(request)
    request.headers['X-Api-Key'] == 'test_api_key' &&
      request.headers['Content-Type'].to_s.include?('multipart/form-data')
  end

  def multipart_field?(request, field_name, value)
    request.body.match?(
      /name="#{Regexp.escape(field_name)}"\r\n\r\n#{Regexp.escape(value.to_s)}\r\n/
    )
  end

  def multipart_file_part?(request, field_name:, filename:, content_type:, contents:)
    request.body.include?(%("#{field_name}"; filename="#{filename}")) &&
      request.body.include?("Content-Type: #{content_type}") &&
      request.body.include?(contents)
  end

  def stub_successful_upload
    stub_request(:post, document_upload_url)
      .with { |request| multipart_request?(request) }
      .to_return(
        status: 200,
        body: { success: true }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_failed_upload(status:, body:)
    stub_request(:post, document_upload_url)
      .with { |request| multipart_request?(request) }
      .to_return(
        status:,
        body: body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def submission
    Form21aDocumentSubmission.find_by!(form21a_attachment_guid:)
  end

  describe '#perform' do
    subject(:perform_job) do
      described_class.new.perform(
        form21a_attachment_guid,
        application_id,
        document_type,
        original_file_name,
        content_type
      )
    end

    context 'when attachment exists and upload succeeds' do
      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(mock_file)
      end

      it 'uploads the document to GCLAWS and deletes the attachment' do
        stub_successful_upload

        expect { perform_job }.to change(FormAttachment, :count).by(-1)
      end

      it 'does not create document submission tracking rows' do
        stub_successful_upload

        expect { perform_job }
          .not_to change(Form21aDocumentSubmission, :count)

        expect(Form21aDocumentSubmissionAttempt.count).to eq(0)
      end

      it 'sends the correct multipart payload to GCLAWS' do
        stub = stub_request(:post, document_upload_url)
               .with do |request|
                 multipart_request?(request) &&
                   multipart_field?(request, 'ApplicationId', application_id) &&
                   multipart_field?(request, 'DocumentTypeId', document_type) &&
                   multipart_field?(request, 'FileTypeId', 7) &&
                   multipart_field?(request, 'OriginalFileName', original_file_name) &&
                   multipart_file_part?(
                     request,
                     field_name: 'FileDetails',
                     filename: original_file_name,
                     content_type:,
                     contents: 'file contents'
                   )
               end
               .to_return(
                 status: 200,
                 body: { success: true }.to_json,
                 headers: { 'Content-Type' => 'application/json' }
               )

        perform_job

        expect(stub).to have_been_requested
      end

      it 'logs success messages' do
        stub_successful_upload

        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:info).with(/Successfully uploaded/)
        expect(Rails.logger).to receive(:info).with(/Deleted Form21aAttachment/)

        perform_job
      end
    end

    context 'when attachment does not exist' do
      it 'logs an error and raises for retry' do
        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:error).with(/Form21aAttachment not found/)

        expect { perform_job }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'records a permanent failed attempt' do
        expect do
          perform_job
        rescue ActiveRecord::RecordNotFound
          nil
        end.to change(Form21aDocumentSubmission, :count).by(1)
                                                        .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

        attempt = submission.submission_attempts.last

        expect(submission.latest_status).to eq('failed_permanent')
        expect(submission.application_id).to eq(application_id)
        expect(submission.document_type).to eq(document_type)
        expect(submission.original_file_name).to eq(original_file_name)
        expect(submission.content_type).to eq(content_type)
        expect(submission.identifiers).to eq(
          'form21a_attachment_guid' => form21a_attachment_guid,
          'application_id' => application_id,
          'document_type' => document_type
        )
        expect(attempt.status).to eq('failed_permanent')
        expect(attempt.failure_classification).to eq('permanent')
        expect(attempt.last_http_status).to be_nil
        expect(attempt.metadata).to include(
          'error_class' => 'ActiveRecord::RecordNotFound',
          'job_class' => described_class.name,
          'form21a_attachment_guid' => form21a_attachment_guid,
          'application_id' => application_id,
          'document_type' => document_type
        )
      end

      it 'does not make an HTTP request' do
        stub = stub_request(:post, document_upload_url)

        expect { perform_job }.to raise_error(ActiveRecord::RecordNotFound)

        expect(stub).not_to have_been_requested
      end
    end

    context 'when attachment returns no file' do
      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(nil)
      end

      it 'logs an error and raises for retry' do
        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:error).with(
          a_string_including(
            'UploadForm21aDocumentToGCLAWSJob: Form21aAttachment returned no file',
            "guid=#{form21a_attachment_guid}",
            "application_id=#{application_id}"
          )
        )

        expect { perform_job }.to raise_error(
          described_class::MissingAttachmentFileError,
          'Form21aAttachment returned no file for document upload'
        )
      end

      it 'records a transient failed attempt' do
        expect do
          perform_job
        rescue described_class::MissingAttachmentFileError
          nil
        end.to change(Form21aDocumentSubmission, :count).by(1)
                                                        .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

        attempt = submission.submission_attempts.last

        expect(submission.latest_status).to eq('failed_transient')
        expect(attempt.status).to eq('failed_transient')
        expect(attempt.failure_classification).to eq('transient')
        expect(attempt.last_http_status).to be_nil
        expect(attempt.error_message).to eq('Form21aAttachment returned no file for document upload')
        expect(attempt.metadata).to include(
          'error_class' => described_class::MissingAttachmentFileError.name,
          'job_class' => described_class.name,
          'form21a_attachment_guid' => form21a_attachment_guid,
          'application_id' => application_id,
          'document_type' => document_type
        )
      end

      it 'does not make an HTTP request' do
        stub = stub_request(:post, document_upload_url)

        expect { perform_job }.to raise_error(described_class::MissingAttachmentFileError)

        expect(stub).not_to have_been_requested
      end
    end

    context 'when file retrieval from S3 fails' do
      let(:s3_error) { Aws::S3::Errors::ServiceError.new(nil, 'S3 connection failed') }

      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file)
          .and_raise(s3_error)
      end

      it 'logs an error and raises the exception for retry' do
        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:error).with(
          a_string_including(
            'UploadForm21aDocumentToGCLAWSJob: Failed to retrieve file',
            "guid=#{form21a_attachment_guid}"
          ),
          exception: s3_error
        )

        expect { perform_job }.to raise_error(Aws::S3::Errors::ServiceError, 'S3 connection failed')
      end

      it 'records a transient failed attempt' do
        expect do
          perform_job
        rescue Aws::S3::Errors::ServiceError
          nil
        end.to change(Form21aDocumentSubmission, :count).by(1)
                                                        .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

        attempt = submission.submission_attempts.last

        expect(submission.latest_status).to eq('failed_transient')
        expect(attempt.status).to eq('failed_transient')
        expect(attempt.failure_classification).to eq('transient')
        expect(attempt.last_http_status).to be_nil
        expect(attempt.error_message).to eq('S3 connection failed')
      end
    end

    context 'when content type is unsupported' do
      let(:content_type) { 'image/png' }

      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(mock_file)
      end

      it 'raises an argument error before making the HTTP request' do
        stub = stub_request(:post, document_upload_url)

        expect { perform_job }.to raise_error(
          ArgumentError,
          'Unsupported content type for Form21aAttachment upload: image/png'
        )

        expect(stub).not_to have_been_requested
      end

      it 'does not delete the attachment' do
        expect do
          perform_job
        rescue ArgumentError
          nil
        end.not_to change(FormAttachment, :count)
      end

      it 'records a permanent failed attempt' do
        expect do
          perform_job
        rescue ArgumentError
          nil
        end.to change(Form21aDocumentSubmission, :count).by(1)
                                                        .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

        attempt = submission.submission_attempts.last

        expect(submission.latest_status).to eq('failed_permanent')
        expect(submission.content_type).to eq('image/png')
        expect(attempt.status).to eq('failed_permanent')
        expect(attempt.failure_classification).to eq('permanent')
        expect(attempt.last_http_status).to be_nil
        expect(attempt.error_message).to eq(
          'Unsupported content type for Form21aAttachment upload: image/png'
        )
      end
    end

    context 'when GCLAWS API returns an error' do
      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(mock_file)
      end

      it 'logs the error and raises for retry' do
        stub_failed_upload(status: 500, body: { error: 'Internal Server Error' })

        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:error).with(/GCLAWS API error/)

        expect { perform_job }.to raise_error(
          described_class::GclawsDocumentUploadError,
          'GCLAWS Document API returned 500'
        )
      end

      it 'does not delete the attachment on failure' do
        stub_failed_upload(status: 500, body: { error: 'Internal Server Error' })

        expect do
          perform_job
        rescue described_class::GclawsDocumentUploadError
          nil
        end.not_to change(FormAttachment, :count)
      end

      it 'records a transient failed attempt for 5xx responses' do
        stub_failed_upload(status: 500, body: { error: 'Internal Server Error' })

        expect do
          perform_job
        rescue described_class::GclawsDocumentUploadError
          nil
        end.to change(Form21aDocumentSubmission, :count).by(1)
                                                        .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

        attempt = submission.submission_attempts.last

        expect(submission.latest_status).to eq('failed_transient')
        expect(submission.application_id).to eq(application_id)
        expect(submission.document_type).to eq(document_type)
        expect(submission.original_file_name).to eq(original_file_name)
        expect(submission.content_type).to eq(content_type)
        expect(submission.identifiers).to eq(
          'form21a_attachment_guid' => form21a_attachment_guid,
          'application_id' => application_id,
          'document_type' => document_type
        )
        expect(attempt.status).to eq('failed_transient')
        expect(attempt.failure_classification).to eq('transient')
        expect(attempt.last_http_status).to eq(500)
        expect(attempt.error_message).to eq('GCLAWS Document API returned 500')
        expect(attempt.response).to eq(
          'status' => 500,
          'body' => {
            'error' => 'Internal Server Error'
          }
        )
      end

      it 'records a permanent failed attempt for 4xx responses' do
        stub_failed_upload(status: 422, body: { error: 'Validation failed' })

        expect do
          perform_job
        rescue described_class::GclawsDocumentUploadError
          nil
        end.to change(Form21aDocumentSubmission, :count).by(1)
                                                        .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

        attempt = submission.submission_attempts.last

        expect(submission.latest_status).to eq('failed_permanent')
        expect(attempt.status).to eq('failed_permanent')
        expect(attempt.failure_classification).to eq('permanent')
        expect(attempt.last_http_status).to eq(422)
        expect(attempt.error_message).to eq('GCLAWS Document API returned 422')
        expect(attempt.response).to eq(
          'status' => 422,
          'body' => {
            'error' => 'Validation failed'
          }
        )
      end

      it 'appends attempts to the existing submission on subsequent failures' do
        stub_failed_upload(status: 500, body: { error: 'Internal Server Error' })

        2.times do
          perform_job
        rescue described_class::GclawsDocumentUploadError
          nil
        end

        expect(Form21aDocumentSubmission.count).to eq(1)
        expect(submission.submission_attempts.count).to eq(2)
        expect(submission.submission_attempts.pluck(:failure_classification)).to eq(
          %w[transient transient]
        )
      end
    end

    context 'when network upload fails' do
      let(:timeout_error) { Faraday::TimeoutError.new('timeout') }

      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(mock_file)

        stub_request(:post, document_upload_url)
          .with { |request| multipart_request?(request) }
          .to_raise(timeout_error)
      end

      it 'logs the network error and raises for retry' do
        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:error).with(
          a_string_including('Network error while uploading document'),
          exception: timeout_error
        )

        expect { perform_job }.to raise_error(Faraday::TimeoutError, 'timeout')
      end

      it 'records a transient failed attempt' do
        expect do
          perform_job
        rescue Faraday::TimeoutError
          nil
        end.to change(Form21aDocumentSubmission, :count).by(1)
                                                        .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

        attempt = submission.submission_attempts.last

        expect(submission.latest_status).to eq('failed_transient')
        expect(attempt.status).to eq('failed_transient')
        expect(attempt.failure_classification).to eq('transient')
        expect(attempt.last_http_status).to be_nil
        expect(attempt.error_message).to eq('timeout')
      end
    end

    context 'when attachment deletion fails after successful upload' do
      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(mock_file)
        allow_any_instance_of(FormAttachment).to receive(:destroy!)
          .and_raise(ActiveRecord::ActiveRecordError, 'delete failed')
      end

      it 'logs the deletion error but does not raise' do
        stub_successful_upload

        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:info).with(/Successfully uploaded/)
        expect(Rails.logger).to receive(:error).with(
          a_string_including('UploadForm21aDocumentToGCLAWSJob: Failed to delete Form21aAttachment'),
          exception: kind_of(ActiveRecord::ActiveRecordError)
        )

        expect { perform_job }.not_to raise_error
      end

      it 'does not create document submission tracking rows' do
        stub_successful_upload

        expect { perform_job }
          .not_to change(Form21aDocumentSubmission, :count)

        expect(Form21aDocumentSubmissionAttempt.count).to eq(0)
      end
    end

    context 'with DOCX file type' do
      let(:content_type) { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }
      let(:original_file_name) { 'test_document.docx' }

      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(mock_file)
      end

      it 'sends FileTypeId 15 for DOCX files' do
        stub = stub_request(:post, document_upload_url)
               .with do |request|
                 multipart_request?(request) &&
                   multipart_field?(request, 'FileTypeId', 15) &&
                   multipart_file_part?(
                     request,
                     field_name: 'FileDetails',
                     filename: original_file_name,
                     content_type:,
                     contents: 'file contents'
                   )
               end
               .to_return(
                 status: 200,
                 body: { success: true }.to_json,
                 headers: { 'Content-Type' => 'application/json' }
               )

        perform_job

        expect(stub).to have_been_requested
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    let(:job) do
      {
        'args' => [
          form21a_attachment_guid,
          application_id,
          document_type,
          original_file_name,
          content_type
        ]
      }
    end
    let(:slack_messenger) { instance_double(VBADocuments::Slack::Messenger, notify!: true) }

    before do
      allow(Rails.logger).to receive(:error)
      allow(VBADocuments::Slack::Messenger).to receive(:new).and_return(slack_messenger)
    end

    it 'records a terminal transient attempt and emits an alert' do
      exception = StandardError.new('Connection failed')

      expect(StatsD).to receive(:increment).with(
        'api.form21a.document_upload.retries_exhausted',
        tags: [
          'classification:transient',
          'terminal_status:failed_transient',
          "document_type:#{document_type}",
          "content_type:#{content_type}"
        ]
      )

      expect do
        described_class.sidekiq_retries_exhausted_block.call(job, exception)
      end.to change(Form21aDocumentSubmission, :count).by(1)
                                                      .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

      attempt = submission.submission_attempts.last

      expect(submission.latest_status).to eq('failed_transient')
      expect(submission.application_id).to eq(application_id)
      expect(submission.document_type).to eq(document_type)
      expect(submission.original_file_name).to eq(original_file_name)
      expect(submission.content_type).to eq(content_type)
      expect(attempt.status).to eq('failed_transient')
      expect(attempt.failure_classification).to eq('transient')
      expect(attempt.last_http_status).to be_nil
      expect(attempt.metadata).to include(
        'terminal' => true,
        'error_class' => 'StandardError',
        'job_class' => described_class.name,
        'form21a_attachment_guid' => form21a_attachment_guid,
        'application_id' => application_id,
        'document_type' => document_type
      )
      expect(attempt.error_message).to eq('Connection failed')
      expect(Rails.logger).to have_received(:error).with(
        a_string_including(
          'UploadForm21aDocumentToGCLAWSJob: All retries exhausted; terminal upload failure recorded.',
          "guid=#{form21a_attachment_guid}",
          "application_id=#{application_id}",
          "document_type=#{document_type}",
          "content_type=#{content_type}",
          'classification=transient',
          'terminal_status=failed_transient'
        ),
        exception:
      )
      expect(VBADocuments::Slack::Messenger).to have_received(:new).with(
        hash_including(
          class: described_class.name,
          alert: '[ALERT] Form 21a document upload retries exhausted: StandardError - Connection failed',
          details: a_string_including(
            "guid: #{form21a_attachment_guid}",
            "application_id: #{application_id}",
            "document_type: #{document_type}",
            "content_type: #{content_type}",
            'classification: transient',
            'terminal_status: failed_transient',
            'exception_class: StandardError',
            'exception_message: Connection failed'
          )
        )
      )
      expect(slack_messenger).to have_received(:notify!)
    end

    it 'truncates long Slack backtraces' do
      exception = StandardError.new('Connection failed')
      exception.set_backtrace(
        Array.new(100) do |index|
          "#{Rails.root}/app/services/example_#{index}.rb:#{index}:in `#{'x' * 200}'"
        end
      )

      allow(StatsD).to receive(:increment)

      described_class.sidekiq_retries_exhausted_block.call(job, exception)

      expect(VBADocuments::Slack::Messenger).to have_received(:new) do |payload|
        details = payload[:details]
        backtrace = details.split("backtrace:\n", 2).last

        expect(details).to include('[APP_ROOT]')
        expect(backtrace).to include('... truncated')
        expect(backtrace.length).to be <= described_class::SLACK_BACKTRACE_CHARACTER_LIMIT + "\n... truncated".length
      end
    end

    it 'records a terminal permanent attempt for permanent failures' do
      exception = described_class::GclawsDocumentUploadError.new(
        422,
        { 'error' => 'Validation failed' }
      )

      allow(StatsD).to receive(:increment)

      expect do
        described_class.sidekiq_retries_exhausted_block.call(job, exception)
      end.to change(Form21aDocumentSubmission, :count).by(1)
                                                      .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

      attempt = submission.submission_attempts.last

      expect(submission.latest_status).to eq('failed_permanent')
      expect(attempt.status).to eq('failed_permanent')
      expect(attempt.failure_classification).to eq('permanent')
      expect(attempt.last_http_status).to eq(422)
      expect(attempt.error_message).to eq('GCLAWS Document API returned 422')
      expect(attempt.response).to eq(
        'status' => 422,
        'body' => {
          'error' => 'Validation failed'
        }
      )
      expect(VBADocuments::Slack::Messenger).to have_received(:new).with(
        hash_including(
          alert: '[ALERT] Form 21a document upload retries exhausted: ' \
                 'AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob::GclawsDocumentUploadError - ' \
                 'GCLAWS Document API returned 422',
          details: a_string_including(
            'classification: permanent',
            'terminal_status: failed_permanent',
            'exception_message: GCLAWS Document API returned 422'
          )
        )
      )
      expect(slack_messenger).to have_received(:notify!)
    end

    it 'logs Slack alert failures without raising' do
      exception = StandardError.new('Connection failed')
      slack_error = StandardError.new('Slack failed')

      allow(StatsD).to receive(:increment)
      allow(slack_messenger).to receive(:notify!).and_raise(slack_error)

      expect do
        described_class.sidekiq_retries_exhausted_block.call(job, exception)
      end.to change(Form21aDocumentSubmission, :count).by(1)
                                                      .and change(Form21aDocumentSubmissionAttempt, :count).by(1)

      expect(Rails.logger).to have_received(:error).with(
        a_string_including(
          'UploadForm21aDocumentToGCLAWSJob: Failed to send Slack alert for exhausted upload.',
          "guid=#{form21a_attachment_guid}",
          "application_id=#{application_id}"
        ),
        exception: slack_error
      )
    end

    it 'does not log or send the original file name when retries are exhausted' do
      exception = StandardError.new('Connection failed')

      allow(StatsD).to receive(:increment)

      described_class.sidekiq_retries_exhausted_block.call(job, exception)

      expect(Rails.logger).not_to have_received(:error).with(
        a_string_including(original_file_name),
        anything
      )
      expect(Rails.logger).not_to have_received(:error).with(
        a_string_including(original_file_name)
      )
      expect(VBADocuments::Slack::Messenger).to have_received(:new) do |payload|
        expect(payload.to_s).not_to include(original_file_name)
      end
    end

    it 'appends the terminal attempt to an existing submission' do
      existing_submission = Form21aDocumentSubmission.create!(
        form_id: '21a',
        application_id:,
        form21a_attachment_guid:,
        document_type:
      )

      Form21aDocumentSubmissionAttempt.create!(
        submission: existing_submission,
        status: 'failed_transient',
        failure_classification: 'transient',
        error_message: 'Previous failure'
      )

      exception = StandardError.new('Connection failed')

      allow(StatsD).to receive(:increment)

      expect do
        described_class.sidekiq_retries_exhausted_block.call(job, exception)
      end.not_to change(Form21aDocumentSubmission, :count)

      expect(existing_submission.reload.submission_attempts.count).to eq(2)
      expect(existing_submission.latest_status).to eq('failed_transient')
      expect(existing_submission.submission_attempts.last.metadata).to include(
        'terminal' => true
      )
      expect(slack_messenger).to have_received(:notify!)
    end
  end
end
