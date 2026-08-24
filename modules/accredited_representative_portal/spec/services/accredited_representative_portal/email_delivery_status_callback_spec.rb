# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::EmailDeliveryStatusCallback do
  let(:base_metadata) do
    {
      'form_number' => 'Form Number',
      'statsd_tags' => {
        'service' => 'representation-management',
        'function' => 'appoint_a_representative_confirmation_email'
      },
      'email_template_id' => '123456789fake'
    }
  end

  let(:confirmation_mail_tags) do
    { tags: { 'function' => 'appoint_a_representative_confirmation_email',
              'service' => 'representation-management' } }
  end

  let(:status_email_tags) do
    { tags: { 'function' => 'callback_status_email', 'service' => 'va_notify' } }
  end

  def build_notification(status:, metadata: base_metadata, to: nil, status_reason: nil)
    VANotify::Notification.new(
      notification_id: SecureRandom.uuid,
      status:,
      notification_type: 'email',
      status_reason:,
      callback_metadata: metadata,
      source_location: 'spec_location',
      to:
    )
  end

  describe '.call' do
    context 'when status is delivered' do
      it 'increments delivery and silent failure metrics' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.notifications.delivered',
          confirmation_mail_tags
        )
        expect(StatsD).to receive(:increment).with(
          'silent_failure_avoided',
          confirmation_mail_tags
        )

        described_class.call(build_notification(status: 'delivered'))
      end
    end

    shared_examples 'a failed delivery status' do |status|
      it "logs error and increments #{status} metric" do
        expect(StatsD).to receive(:increment).with(
          "api.vanotify.notifications.#{status}",
          confirmation_mail_tags
        )
        expect(Rails.logger).to receive(:error).with(
          a_string_including(%("status":"#{status}"))
        )

        described_class.call(build_notification(status:))
      end
    end

    include_examples 'a failed delivery status', 'permanent-failure'
    include_examples 'a failed delivery status', 'temporary-failure'

    context 'when the recipient is a known Staging placeholder address' do
      let(:fake_email) { 'representative-123@example.com' }
      let(:tags_with_recipient_type) do
        { tags: confirmation_mail_tags[:tags].merge('recipient_type' => 'test') }
      end

      AccreditedRepresentativePortal::EmailDeliveryStatusCallback::ADDRESS_FAILURE_STATUS_REASONS.each do |reason|
        context "and status_reason is \"#{reason}\"" do
          %w[permanent-failure temporary-failure].each do |status|
            it "adds the recipient_type:test tag to the #{status} metric" do
              expect(StatsD).to receive(:increment).with(
                "api.vanotify.notifications.#{status}",
                tags_with_recipient_type
              )

              described_class.call(
                build_notification(status:, to: fake_email, status_reason: reason)
              )
            end
          end
        end
      end

      context 'but the failure is unrelated to the address' do
        it 'does not add the recipient_type:test tag' do
          expect(StatsD).to receive(:increment).with(
            'api.vanotify.notifications.permanent-failure',
            confirmation_mail_tags
          )

          described_class.call(
            build_notification(status: 'permanent-failure', to: fake_email, status_reason: 'VA Notify technical error')
          )
        end
      end

      context 'when delivered' do
        it 'does not add the recipient_type:test tag' do
          expect(StatsD).to receive(:increment).with(
            'api.vanotify.notifications.delivered',
            confirmation_mail_tags
          )
          expect(StatsD).to receive(:increment).with(
            'silent_failure_avoided',
            confirmation_mail_tags
          )

          described_class.call(build_notification(status: 'delivered', to: fake_email))
        end
      end

      context 'but reading the recipient address raises an error' do
        let(:unreadable_notification) do
          build_notification(
            status: 'permanent-failure', to: fake_email,
            status_reason: 'Email address is in invalid format'
          ).tap do |notification|
            allow(notification).to receive(:to).and_raise(StandardError, 'boom')
          end
        end

        it 'treats the recipient as not fake' do
          expect(described_class.fake_email_address?(unreadable_notification)).to be(false)
        end

        it 'does not add the recipient_type:test tag and still reports the failure' do
          expect(StatsD).to receive(:increment).with(
            'api.vanotify.notifications.permanent-failure',
            confirmation_mail_tags
          )

          described_class.call(unreadable_notification)
        end
      end
    end

    context 'when the recipient is a real address' do
      it 'does not add the recipient_type:test tag even with an address-related failure reason' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.notifications.permanent-failure',
          confirmation_mail_tags
        )

        described_class.call(
          build_notification(
            status: 'permanent-failure',
            to: 'real.representative@va.gov',
            status_reason: 'Email address is in invalid format'
          )
        )
      end
    end

    context 'when status is unrecognized' do
      it 'logs a warning and increments other metric' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.notifications.other',
          confirmation_mail_tags
        )
        expect(Rails.logger).to receive(:warn).with(
          a_string_including('"message":"Unhandled callback status"')
        )

        described_class.call(build_notification(status: 'some-weird-status'))
      end
    end

    context 'when callback_metadata is missing statsd_tags' do
      it 'uses fallback service and function tags' do
        metadata = { 'form_number' => 'Form Number' } # missing statsd_tags

        expect(StatsD).to receive(:increment).with(
          'api.vanotify.notifications.delivered',
          status_email_tags
        )
        expect(StatsD).to receive(:increment).with(
          'silent_failure_avoided',
          status_email_tags
        )

        described_class.call(build_notification(status: 'delivered', metadata:))
      end
    end
  end
end
