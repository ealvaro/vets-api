# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VANotify::InProgressFormReminderCallback do
  let(:in_progress_form_id) { 123 }
  let(:attempt) { 1 }
  let(:metadata) do
    {
      'notification_type' => 'in_progress_reminder',
      'form_number' => '21-526EZ',
      'in_progress_form_id' => in_progress_form_id,
      'attempt' => attempt,
      'statsd_tags' => {
        'service' => 'va-notify',
        'function' => '21-526EZ in progress reminder'
      }
    }
  end

  let(:base_tags) do
    ['service:va-notify', 'function:21-526EZ in progress reminder', 'form_number:21-526EZ']
  end

  def build_notification(status:, status_reason: nil, callback_metadata: metadata)
    VANotify::Notification.new(
      notification_id: SecureRandom.uuid,
      status:,
      status_reason:,
      notification_type: 'email',
      template_id: 'some-template-id',
      callback_metadata:,
      source_location: 'spec_location'
    )
  end

  before do
    allow(Rails.logger).to receive(:warn)
    allow(Flipper).to receive(:enabled?).with(:in_progress_form_reminder_retry).and_return(false)
  end

  describe '.call' do
    context 'when the reminder was delivered' do
      it 'increments the delivered metric' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.in_progress_form_reminder.delivered',
          tags: base_tags + ['reason:none']
        )

        described_class.call(build_notification(status: 'delivered'))
      end

      it 'does not touch the silent failure metrics' do
        allow(StatsD).to receive(:increment)

        described_class.call(build_notification(status: 'delivered'))

        expect(StatsD).not_to have_received(:increment).with('silent_failure_avoided', anything)
        expect(StatsD).not_to have_received(:increment).with('silent_failure', anything)
      end
    end

    context 'when the reminder permanently failed' do
      let(:status_reason) { 'Undeliverable - No VA Profile contact information' }

      it 'increments the permanent failure metric tagged with the reason' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.in_progress_form_reminder.permanent_failure',
          tags: base_tags + ['reason:undeliverable_no_va_profile_contact_information']
        )

        described_class.call(build_notification(status: 'permanent-failure', status_reason:))
      end

      it 'logs the failure at warn rather than as an application error' do
        allow(StatsD).to receive(:increment)
        expect(Rails.logger).not_to receive(:error)

        described_class.call(build_notification(status: 'permanent-failure', status_reason:))

        expect(Rails.logger).to have_received(:warn).with(
          'VANotify in progress reminder undelivered',
          hash_including(status: 'permanent-failure', status_reason:, form_number: '21-526EZ')
        )
      end

      it 'does not increment the silent failure metric' do
        allow(StatsD).to receive(:increment)

        described_class.call(build_notification(status: 'permanent-failure', status_reason:))

        expect(StatsD).not_to have_received(:increment).with('silent_failure', anything)
      end
    end

    context 'when the reminder temporarily failed' do
      let(:status_reason) do
        'Retryable - Notification is unable to be processed at this time. Replay the request to VA Notify.'
      end
      let(:reason_tag) do
        'reason:retryable_notification_is_unable_to_be_processed_at_this_time_' \
          'replay_the_request_to_va_notify'
      end

      it 'increments the temporary failure metric tagged with the reason' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.in_progress_form_reminder.temporary_failure',
          tags: base_tags + [reason_tag]
        )

        described_class.call(build_notification(status: 'temporary-failure', status_reason:))
      end

      context 'and the retry is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:in_progress_form_reminder_retry).and_return(true)
          allow(StatsD).to receive(:increment)
          allow(VANotify::InProgressFormReminder).to receive(:perform_in)
        end

        it 're-runs the reminder for the same form with the attempt bumped' do
          described_class.call(build_notification(status: 'temporary-failure', status_reason:))

          expect(VANotify::InProgressFormReminder).to have_received(:perform_in)
            .with(described_class::RETRY_DELAY, in_progress_form_id, 2)
          expect(StatsD).to have_received(:increment)
            .with('api.vanotify.in_progress_form_reminder.retry_queued', tags: base_tags + [reason_tag])
        end

        context 'and the send was the multi-form reminder' do
          let(:metadata) do
            { 'notification_type' => 'in_progress_reminder', 'form_number' => 'multiple',
              'in_progress_form_id' => in_progress_form_id, 'attempt' => attempt,
              'statsd_tags' => { 'service' => 'va-notify', 'function' => 'multiple in progress reminder' } }
          end

          it 're-runs the form that anchored the send, not the form_number' do
            described_class.call(build_notification(status: 'temporary-failure', status_reason:))

            expect(VANotify::InProgressFormReminder).to have_received(:perform_in)
              .with(described_class::RETRY_DELAY, in_progress_form_id, 2)
          end
        end

        context 'and the attempts are used up' do
          let(:attempt) { described_class::MAX_ATTEMPTS }

          it 'gives up and records that rather than re-sending' do
            described_class.call(build_notification(status: 'temporary-failure', status_reason:))

            expect(VANotify::InProgressFormReminder).not_to have_received(:perform_in)
            expect(StatsD).to have_received(:increment)
              .with('api.vanotify.in_progress_form_reminder.retries_exhausted', tags: base_tags + [reason_tag])
          end
        end

        context 'and the metadata predates the retry support' do
          let(:metadata) do
            { 'notification_type' => 'in_progress_reminder', 'form_number' => '21-526EZ',
              'statsd_tags' => { 'service' => 'va-notify', 'function' => '21-526EZ in progress reminder' } }
          end

          it 'does not attempt a re-send, and counts the skip' do
            described_class.call(build_notification(status: 'temporary-failure', status_reason:))

            expect(VANotify::InProgressFormReminder).not_to have_received(:perform_in)
            expect(StatsD).to have_received(:increment)
              .with('api.vanotify.in_progress_form_reminder.retry_skipped', tags: base_tags + [reason_tag])
          end
        end

        context 'and queueing the re-send fails' do
          before do
            allow(VANotify::InProgressFormReminder).to receive(:perform_in).and_raise(Redis::BaseError, 'no redis')
            allow(Rails.logger).to receive(:error)
          end

          it 'counts the failure and re-raises rather than dropping the reminder silently' do
            expect do
              described_class.call(build_notification(status: 'temporary-failure', status_reason:))
            end.to raise_error(Redis::BaseError)

            expect(StatsD).to have_received(:increment)
              .with('api.vanotify.in_progress_form_reminder.retry_queue_failed', tags: base_tags + [reason_tag])
            expect(Rails.logger).to have_received(:error)
              .with('VANotify in progress reminder retry could not be queued', hash_including(error: 'no redis'))
          end
        end
      end

      context 'and the retry is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:in_progress_form_reminder_retry).and_return(false)
          allow(StatsD).to receive(:increment)
          allow(VANotify::InProgressFormReminder).to receive(:perform_in)
        end

        it 'still counts the failure but does not re-send' do
          described_class.call(build_notification(status: 'temporary-failure', status_reason:))

          expect(VANotify::InProgressFormReminder).not_to have_received(:perform_in)
          expect(StatsD).to have_received(:increment)
            .with('api.vanotify.in_progress_form_reminder.temporary_failure', tags: base_tags + [reason_tag])
        end
      end
    end

    context 'when the status is not one we handle' do
      it 'increments the catch-all metric' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.in_progress_form_reminder.other',
          tags: base_tags + ['reason:none']
        )

        described_class.call(build_notification(status: 'sending'))
      end
    end

    context 'when the callback metadata is missing' do
      it 'still records the failure without raising' do
        expect(StatsD).to receive(:increment).with(
          'api.vanotify.in_progress_form_reminder.permanent_failure',
          tags: ['reason:undeliverable_individual_unreachable']
        )

        expect do
          described_class.call(
            build_notification(status: 'permanent-failure',
                               status_reason: 'Undeliverable - Individual unreachable',
                               callback_metadata: nil)
          )
        end.not_to raise_error
      end
    end
  end
end
