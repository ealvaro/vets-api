# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::RunUnsuccessful21aUploads, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  subject(:perform_job) { described_class.new.perform }

  let(:application_id) { '12345' }
  let(:document_type) { known_document_type }

  let(:known_document_type) do
    AccreditedRepresentativePortal::Form21aDocumentUploadConstants::DOCUMENT_TYPES.values.first
  end
  let(:content_type) { 'application/pdf' }
  let(:original_file_name) { 'test_document.pdf' }
  let(:slack_messenger) { instance_double(VBADocuments::Slack::Messenger, notify!: true) }

  before do
    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(VBADocuments::Slack::Messenger).to receive(:new).and_return(slack_messenger)
    allow(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob).to receive(:perform_async)
  end

  def create_submission(attributes = {})
    submission = Form21aDocumentSubmission.create!(
      {
        form_id: '21a',
        application_id:,
        form21a_attachment_guid: SecureRandom.uuid,
        document_type:,
        content_type:
      }.merge(attributes.except(:original_file_name, :identifiers))
    )

    submission.original_file_name = attributes.fetch(:original_file_name, original_file_name)
    submission.identifiers = attributes.fetch(
      :identifiers,
      {
        'form21a_attachment_guid' => submission.form21a_attachment_guid,
        'application_id' => submission.application_id,
        'document_type' => submission.document_type
      }
    )
    submission.save!

    submission
  end

  def create_attempt(submission, attributes = {})
    Form21aDocumentSubmissionAttempt.create!(
      {
        submission:,
        status: 'failed_transient',
        failure_classification: 'transient',
        attempted_at: 1.minute.ago
      }.merge(attributes)
    )
  end

  def create_attempts(submission, count:, status: 'failed_transient')
    count.times do
      create_attempt(
        submission,
        status:,
        failure_classification: status == 'failed_transient' ? 'transient' : nil
      )
    end
  end

  def create_redrivable_submission(attributes = {})
    submission = create_submission(
      {
        latest_status: 'failed_transient',
        next_retry_at: 1.minute.ago
      }.merge(attributes)
    )

    create_attempt(submission)

    submission.reload
  end

  describe 'Sidekiq configuration' do
    it 'uses bounded retries' do
      expect(described_class.sidekiq_options['retry']).to eq(7)
    end

    it 'sets uniqueness for the cron cadence' do
      expect(described_class.sidekiq_options['unique_for']).to eq(2.hours)
    end
  end

  describe '#perform' do
    it 're-enqueues one due failed_transient document per application as a probe' do
      first_submission = create_redrivable_submission(created_at: 3.minutes.ago)
      create_redrivable_submission(created_at: 2.minutes.ago)
      create_redrivable_submission(created_at: 1.minute.ago)

      perform_job

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).once.with(
          first_submission.form21a_attachment_guid,
          first_submission.application_id,
          first_submission.document_type,
          first_submission.original_file_name,
          first_submission.content_type
        )
    end

    it 'probes one document for each application' do
      first_application_submission = create_redrivable_submission(
        application_id: '12345',
        created_at: 2.minutes.ago
      )
      second_application_submission = create_redrivable_submission(
        application_id: '67890',
        created_at: 2.minutes.ago
      )

      create_redrivable_submission(
        application_id: '12345',
        created_at: 1.minute.ago
      )
      create_redrivable_submission(
        application_id: '67890',
        created_at: 1.minute.ago
      )

      perform_job

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).with(
          first_application_submission.form21a_attachment_guid,
          first_application_submission.application_id,
          first_application_submission.document_type,
          first_application_submission.original_file_name,
          first_application_submission.content_type
        )

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).with(
          second_application_submission.form21a_attachment_guid,
          second_application_submission.application_id,
          second_application_submission.document_type,
          second_application_submission.original_file_name,
          second_application_submission.content_type
        )

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).twice
    end

    it 'drains the rest of an application after a previous probe has succeeded' do
      succeeded_submission = create_submission(
        application_id:,
        latest_status: 'succeeded',
        succeeded_at: 1.minute.ago
      )
      create_attempt(
        succeeded_submission,
        status: 'succeeded',
        failure_classification: nil
      )

      first_redrivable = create_redrivable_submission(
        application_id:,
        created_at: 2.minutes.ago
      )
      second_redrivable = create_redrivable_submission(
        application_id:,
        created_at: 1.minute.ago
      )

      perform_job

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).with(
          first_redrivable.form21a_attachment_guid,
          first_redrivable.application_id,
          first_redrivable.document_type,
          first_redrivable.original_file_name,
          first_redrivable.content_type
        )

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).with(
          second_redrivable.form21a_attachment_guid,
          second_redrivable.application_id,
          second_redrivable.document_type,
          second_redrivable.original_file_name,
          second_redrivable.content_type
        )

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).twice
    end

    it 'sets backoff before re-enqueuing a document' do
      submission = create_redrivable_submission
      now = Time.current.change(usec: 0)

      travel_to now do
        perform_job

        expect(submission.reload.last_attempted_at).to eq(now)
        expect(submission.next_retry_at).to eq(
          now + described_class::BACKOFF_SCHEDULE.first
        )
      end
    end

    it 'skips a document on the next cycle when backoff has pushed next_retry_at into the future' do
      submission = create_redrivable_submission

      perform_job

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).once

      next_retry_at = submission.reload.next_retry_at

      described_class.new.perform

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .to have_received(:perform_async).once

      expect(submission.reload.next_retry_at).to eq(next_retry_at)
      expect(submission.next_retry_at).to be > Time.current
    end

    it 'emits a redrive metric and log when enqueueing' do
      submission = create_redrivable_submission

      perform_job

      expect(StatsD).to have_received(:increment).with(
        'api.form21a.document_upload.redrive_enqueued',
        tags: [
          "document_type:#{submission.document_type}",
          "content_type:#{submission.content_type}"
        ]
      )

      expect(Rails.logger).to have_received(:info).with(
        a_string_including(
          'RunUnsuccessful21aUploads: Re-enqueued Form 21a document upload.',
          "guid=#{submission.form21a_attachment_guid}",
          "application_id=#{submission.application_id}",
          "document_type=#{submission.document_type}"
        )
      )
    end

    it 'collapses unknown Datadog document and content type tags to other' do
      create_redrivable_submission(
        document_type: 99_999,
        content_type: 'application/unknown'
      )

      perform_job

      expect(StatsD).to have_received(:increment).with(
        'api.form21a.document_upload.redrive_enqueued',
        tags: [
          'document_type:other',
          'content_type:other'
        ]
      )
    end

    it 'does not re-drive failed_permanent documents' do
      submission = create_submission(
        latest_status: 'failed_permanent',
        next_retry_at: 1.minute.ago
      )
      create_attempt(
        submission,
        status: 'failed_permanent',
        failure_classification: 'permanent'
      )

      perform_job

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .not_to have_received(:perform_async)
    end

    it 'does not re-drive succeeded documents' do
      submission = create_submission(
        latest_status: 'succeeded',
        next_retry_at: 1.minute.ago,
        succeeded_at: 1.minute.ago
      )
      create_attempt(
        submission,
        status: 'succeeded',
        failure_classification: nil
      )

      perform_job

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .not_to have_received(:perform_async)
    end

    it 'does not re-drive abandoned documents' do
      submission = create_submission(
        latest_status: 'abandoned',
        next_retry_at: 1.minute.ago
      )
      create_attempt(
        submission,
        status: 'abandoned',
        failure_classification: nil
      )

      perform_job

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .not_to have_received(:perform_async)
    end

    it 'abandons a document that has reached the max attempt count and does not re-enqueue it' do
      submission = create_submission(
        latest_status: 'failed_transient',
        next_retry_at: 1.minute.ago
      )
      create_attempts(
        submission,
        count: Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS
      )

      expect do
        perform_job
      end.to change(Form21aDocumentSubmissionAttempt, :count).by(1)

      submission.reload
      abandoned_attempt = submission.submission_attempts.last

      expect(submission.latest_status).to eq('abandoned')
      expect(submission.next_retry_at).to be_nil
      expect(submission.last_attempted_at).to be_present
      expect(abandoned_attempt.status).to eq('abandoned')
      expect(abandoned_attempt.metadata).to include(
        'job_class' => described_class.name,
        'reason' => 'max_redrive_attempts_reached',
        'form21a_attachment_guid' => submission.form21a_attachment_guid,
        'application_id' => submission.application_id,
        'document_type' => submission.document_type,
        'attempt_count' => Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS,
        'redrive_max_attempts' => Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS
      )

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .not_to have_received(:perform_async)
    end

    it 'abandons a document older than the abandon threshold and does not re-enqueue it' do
      submission = create_redrivable_submission

      # rubocop:disable Rails/SkipsModelValidations
      submission.update_columns(
        created_at: Form21aDocumentSubmission::ABANDON_THRESHOLD.ago - 1.minute
      )
      # rubocop:enable Rails/SkipsModelValidations
      expect do
        perform_job
      end.to change(Form21aDocumentSubmissionAttempt, :count).by(1)

      submission.reload
      abandoned_attempt = submission.submission_attempts.last

      expect(submission.latest_status).to eq('abandoned')
      expect(submission.next_retry_at).to be_nil
      expect(abandoned_attempt.status).to eq('abandoned')
      expect(abandoned_attempt.metadata).to include(
        'reason' => 'abandon_threshold_exceeded'
      )

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .not_to have_received(:perform_async)
    end

    it 'abandons pending stragglers older than the abandon threshold' do
      submission = create_submission(latest_status: 'pending')

      # rubocop:disable Rails/SkipsModelValidations
      submission.update_columns(
        created_at: Form21aDocumentSubmission::ABANDON_THRESHOLD.ago - 1.minute
      )
      # rubocop:enable Rails/SkipsModelValidations

      expect do
        perform_job
      end.to change(Form21aDocumentSubmissionAttempt, :count).by(1)

      submission.reload
      abandoned_attempt = submission.submission_attempts.last

      expect(submission.latest_status).to eq('abandoned')
      expect(submission.next_retry_at).to be_nil
      expect(submission.last_attempted_at).to be_present
      expect(abandoned_attempt.status).to eq('abandoned')
      expect(abandoned_attempt.metadata).to include(
        'reason' => 'abandon_threshold_exceeded'
      )

      expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
        .not_to have_received(:perform_async)
    end

    it 'alerts when a document is abandoned' do
      submission = create_submission(
        latest_status: 'failed_transient',
        next_retry_at: 1.minute.ago
      )
      create_attempts(
        submission,
        count: Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS
      )

      perform_job

      expect(StatsD).to have_received(:increment).with(
        'api.form21a.document_upload.abandoned',
        tags: [
          "document_type:#{submission.document_type}",
          "content_type:#{submission.content_type}",
          'reason:max_redrive_attempts_reached'
        ]
      )

      expect(Rails.logger).to have_received(:error).with(
        a_string_including(
          'RunUnsuccessful21aUploads: Form 21a document upload abandoned.',
          "guid=#{submission.form21a_attachment_guid}",
          "application_id=#{submission.application_id}",
          "document_type=#{submission.document_type}",
          'latest_status=abandoned',
          "attempt_count=#{Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS}",
          'reason=max_redrive_attempts_reached'
        )
      )

      expect(VBADocuments::Slack::Messenger).to have_received(:new).with(
        hash_including(
          class: described_class.name,
          alert: '[ALERT] Form 21a document upload abandoned',
          details: a_string_including(
            "guid: #{submission.form21a_attachment_guid}",
            "application_id: #{submission.application_id}",
            "document_type: #{submission.document_type}",
            "content_type: #{submission.content_type}",
            'latest_status: abandoned',
            "attempt_count: #{Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS}",
            'reason: max_redrive_attempts_reached'
          )
        )
      )
      expect(slack_messenger).to have_received(:notify!)
    end

    it 'surfaces stuck pending stragglers' do
      submission = create_submission(latest_status: 'pending')
      # rubocop:disable Rails/SkipsModelValidations
      submission.update_columns(
        created_at: Form21aDocumentSubmission::STUCK_THRESHOLD.ago - 1.minute
      )
      # rubocop:enable Rails/SkipsModelValidations
      perform_job

      expect(StatsD).to have_received(:increment).with(
        'api.form21a.document_upload.stuck',
        tags: [
          "document_type:#{submission.document_type}",
          "content_type:#{submission.content_type}",
          'latest_status:pending'
        ]
      )

      expect(Rails.logger).to have_received(:error).with(
        a_string_including(
          'RunUnsuccessful21aUploads: Form 21a document upload is stuck in non-terminal status.',
          "guid=#{submission.form21a_attachment_guid}",
          "application_id=#{submission.application_id}",
          "document_type=#{submission.document_type}",
          'latest_status=pending'
        )
      )

      expect(VBADocuments::Slack::Messenger).to have_received(:new).with(
        hash_including(
          class: described_class.name,
          alert: '[ALERT] Form 21a document upload stuck in non-terminal status',
          details: a_string_including(
            "guid: #{submission.form21a_attachment_guid}",
            "application_id: #{submission.application_id}",
            "document_type: #{submission.document_type}",
            "content_type: #{submission.content_type}",
            'latest_status: pending'
          )
        )
      )
      expect(slack_messenger).to have_received(:notify!)
      expect(submission.reload.last_stuck_alerted_at).to be_present
    end

    it 'surfaces stuck uploading stragglers' do
      submission = create_submission(latest_status: 'uploading')
      # rubocop:disable Rails/SkipsModelValidations
      submission.update_columns(
        created_at: Form21aDocumentSubmission::STUCK_THRESHOLD.ago - 1.minute
      )
      # rubocop:enable Rails/SkipsModelValidations
      perform_job

      expect(StatsD).to have_received(:increment).with(
        'api.form21a.document_upload.stuck',
        tags: [
          "document_type:#{submission.document_type}",
          "content_type:#{submission.content_type}",
          'latest_status:uploading'
        ]
      )

      expect(VBADocuments::Slack::Messenger).to have_received(:new).with(
        hash_including(
          alert: '[ALERT] Form 21a document upload stuck in non-terminal status'
        )
      )

      expect(submission.reload.last_stuck_alerted_at).to be_present
    end

    it 'does not repeatedly alert on stuck records inside the throttle window' do
      submission = create_submission(
        latest_status: 'pending',
        last_stuck_alerted_at: 1.hour.ago
      )
      # rubocop:disable Rails/SkipsModelValidations
      submission.update_columns(
        created_at: Form21aDocumentSubmission::STUCK_THRESHOLD.ago - 1.minute
      )
      # rubocop:enable Rails/SkipsModelValidations
      perform_job

      expect(StatsD).not_to have_received(:increment).with(
        'api.form21a.document_upload.stuck',
        anything
      )

      expect(VBADocuments::Slack::Messenger).not_to have_received(:new)
    end

    it 'alerts again when a stuck alert is older than the throttle window' do
      submission = create_submission(
        latest_status: 'pending',
        last_stuck_alerted_at: described_class::STUCK_ALERT_THROTTLE.ago - 1.minute
      )
      # rubocop:disable Rails/SkipsModelValidations
      submission.update_columns(
        created_at: Form21aDocumentSubmission::STUCK_THRESHOLD.ago - 1.minute
      )
      # rubocop:enable Rails/SkipsModelValidations
      perform_job

      expect(StatsD).to have_received(:increment).with(
        'api.form21a.document_upload.stuck',
        tags: [
          "document_type:#{submission.document_type}",
          "content_type:#{submission.content_type}",
          'latest_status:pending'
        ]
      )

      expect(submission.reload.last_stuck_alerted_at).to be > described_class::STUCK_ALERT_THROTTLE.ago
    end

    it 'does not alert on recent pending records' do
      create_submission(latest_status: 'pending')

      perform_job

      expect(StatsD).not_to have_received(:increment).with(
        'api.form21a.document_upload.stuck',
        anything
      )

      expect(VBADocuments::Slack::Messenger).not_to have_received(:new)
    end

    it 'logs Slack alert failures without raising' do
      submission = create_submission(
        latest_status: 'failed_transient',
        next_retry_at: 1.minute.ago
      )
      create_attempts(
        submission,
        count: Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS
      )

      slack_error = StandardError.new('Slack failed')
      allow(slack_messenger).to receive(:notify!).and_raise(slack_error)

      expect { perform_job }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(
        'RunUnsuccessful21aUploads: Failed to send Slack alert.',
        exception: slack_error
      )
    end
  end
end
