# frozen_string_literal: true

require './modules/decision_reviews/spec/dr_spec_helper'
require 'decision_reviews/notification_callbacks/form_notification_callback'

describe DecisionReviews::FormNotificationCallback do
  subject { described_class }

  let(:submitted_appeal_uuid) { SecureRandom.uuid }
  let(:reference) { "SC-form-#{submitted_appeal_uuid}" }
  let(:email_template_id) do
    Settings.vanotify.services.benefits_decision_review.template_id.supplemental_claim_form_error_email
  end

  let(:callback_metadata) do
    {
      email_type: 'error',
      service_name: 'supplemental-claims',
      function: 'form_submission_to_lighthouse',
      submitted_appeal_uuid:,
      email_template_id:,
      reference:,
      statsd_tags: ['service:supplemental-claims', 'function:form_submission_to_lighthouse']
    }
  end

  # A persisted VANotify::Notification reloaded from the database so that
  # `callback_metadata` is returned from the jsonb column with string keys.
  # This mirrors what `VANotify::DeliveryStatusUpdateJob` sees in production
  # (it loads the record fresh before invoking the callback) and is what
  # exposed the symbol/string-key mismatch in `NotificationMonitor`.
  let(:notification) do
    create(
      :notification,
      notification_type: 'email',
      status:,
      status_reason:,
      callback_klass: described_class.to_s,
      callback_metadata:
    ).reload
  end

  before do
    allow(DecisionReviewNotificationAuditLog).to receive(:create!)
    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:info)
  end

  context 'when the notification is delivered' do
    let(:status) { 'delivered' }
    let(:status_reason) { 'success' }

    it 'records and logs a successful form notification delivery' do
      expect(Rails.logger).to receive(:error) do |message, payload|
        expect(message).to eq('Silent failure avoided')
        expect(payload[:service]).to eq('supplemental-claims')
        expect(payload[:function]).to eq('form_submission_to_lighthouse')
        expect(payload[:additional_context][:callback_metadata]['submitted_appeal_uuid'])
          .to eq(submitted_appeal_uuid)
      end
      expect(Rails.logger).to receive(:info).with('DecisionReviews::FormNotificationCallback: Delivered',
                                                  anything)

      subject.call(notification)

      expect(DecisionReviewNotificationAuditLog).to have_received(:create!).with(
        notification_id: notification.notification_id,
        reference:,
        status: 'delivered',
        payload: notification.to_json
      )

      statsd = 'api.veteran_facing_services.notification_callback.delivered'
      tags = include('service:supplemental-claims', 'function:form_submission_to_lighthouse')
      expect(StatsD).to have_received(:increment).with('silent_failure_avoided', tags:).exactly(1).time
      expect(StatsD).to have_received(:increment).with(statsd, tags:).exactly(1).time
    end
  end

  context 'when the notification permanently fails' do
    let(:status) { 'permanent-failure' }
    let(:status_reason) { 'failure' }

    it 'records and logs a permanently failed form notification delivery' do
      expect(Rails.logger).to receive(:error) do |message, payload|
        expect(message).to eq('Silent failure!')
        expect(payload[:service]).to eq('supplemental-claims')
        expect(payload[:function]).to eq('form_submission_to_lighthouse')
        expect(payload[:additional_context][:callback_metadata]['submitted_appeal_uuid'])
          .to eq(submitted_appeal_uuid)
      end
      expect(Rails.logger).to receive(:error).with('DecisionReviews::FormNotificationCallback: Permanent Failure',
                                                   anything)

      subject.call(notification)

      expect(DecisionReviewNotificationAuditLog).to have_received(:create!).with(
        notification_id: notification.notification_id,
        reference:,
        status: 'permanent-failure',
        payload: notification.to_json
      )

      statsd = 'api.veteran_facing_services.notification_callback.permanent_failure'
      tags = include('service:supplemental-claims', 'function:form_submission_to_lighthouse')
      expect(StatsD).to have_received(:increment).with('silent_failure', tags:).exactly(1).time
      expect(StatsD).to have_received(:increment).with(statsd, tags:).exactly(1).time
    end
  end

  context 'when the notification temporarily fails' do
    let(:status) { 'temporary-failure' }
    let(:status_reason) { 'failure' }

    it 'records and logs a temporarily failed form notification delivery' do
      expect(Rails.logger).to receive(:warn).with('DecisionReviews::FormNotificationCallback: Temporary Failure',
                                                  anything)

      subject.call(notification)

      expect(DecisionReviewNotificationAuditLog).to have_received(:create!).with(
        notification_id: notification.notification_id,
        reference:,
        status: 'temporary-failure',
        payload: notification.to_json
      )

      statsd = 'api.veteran_facing_services.notification_callback.temporary_failure'
      tags = include('service:supplemental-claims', 'function:form_submission_to_lighthouse')
      expect(StatsD).to have_received(:increment).with(statsd, tags:).exactly(1).time
    end
  end

  context 'when the notification has some other status' do
    let(:status) { 'other' }
    let(:status_reason) { 'unknown' }
    let(:callback_metadata) do
      {
        email_type: 'error',
        form_id: '995',
        submitted_appeal_uuid:,
        email_template_id:,
        service_name: 'supplemental-claims',
        reference:,
        statsd_tags: ['service:supplemental-claims', 'function:form_submission_to_lighthouse']
      }
    end

    it 'records an audit log for the other status' do
      expect(Rails.logger).to receive(:warn).with('DecisionReviews::FormNotificationCallback: Other',
                                                  anything)

      subject.call(notification)

      expect(DecisionReviewNotificationAuditLog).to have_received(:create!).with(
        notification_id: notification.notification_id,
        reference:,
        status: 'other',
        payload: notification.to_json
      )
    end
  end
end
