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

      it 'does not make an HTTP request' do
        stub = stub_request(:post, document_upload_url)

        expect { perform_job }.to raise_error(ActiveRecord::RecordNotFound)

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
    end

    context 'when GCLAWS API returns an error' do
      before do
        form21a_attachment
        allow_any_instance_of(FormAttachment).to receive(:get_file).and_return(mock_file)
      end

      it 'logs the error and raises for retry' do
        stub_request(:post, document_upload_url)
          .with { |request| multipart_request?(request) }
          .to_return(
            status: 500,
            body: { error: 'Internal Server Error' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect(Rails.logger).to receive(:info).with(/Starting upload/)
        expect(Rails.logger).to receive(:error).with(/GCLAWS API error/)

        expect { perform_job }.to raise_error(
          described_class::GclawsDocumentUploadError,
          'GCLAWS Document API returned 500'
        )
      end

      it 'does not delete the attachment on failure' do
        stub_request(:post, document_upload_url)
          .with { |request| multipart_request?(request) }
          .to_return(
            status: 500,
            body: { error: 'Internal Server Error' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect do
          perform_job
        rescue described_class::GclawsDocumentUploadError
          nil
        end.not_to change(FormAttachment, :count)
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
    it 'logs an error when all retries are exhausted' do
      job = { 'args' => [form21a_attachment_guid, application_id, document_type, original_file_name, content_type] }
      exception = StandardError.new('Connection failed')

      expect(Rails.logger).to receive(:error).with(
        a_string_including(
          'UploadForm21aDocumentToGCLAWSJob: All retries exhausted.',
          "guid=#{form21a_attachment_guid}",
          "application_id=#{application_id}",
          "document_type=#{document_type}",
          "content_type=#{content_type}"
        ),
        exception:
      )

      described_class.sidekiq_retries_exhausted_block.call(job, exception)
    end
  end
end
