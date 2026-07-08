# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::VANotifyFollowUpJob, type: :job do
  subject { described_class.new }

  describe '#perform' do
    before do
      allow_any_instance_of(described_class).to receive(:handle_failure).and_return(true)
    end

    let(:notification_id) { '111111-1111-1111-11111111' }
    let(:temp) { create(:power_of_attorney, :with_full_headers) }
    let(:attempt) { 0 }

    context 'queue up the job' do
      before do
        allow_any_instance_of(described_class).to receive(:notification_response_status).and_return('delivered')
      end

      it 'queues up with just the notification_id' do
        expect do
          subject.perform(notification_id)
        end.not_to raise_error
      end

      it 'queues up with notification_id and poa_id' do
        expect do
          subject.perform(notification_id, temp.id)
        end.not_to raise_error
      end

      it 'queues up with notification_id, poa_id, and attempt' do
        expect do
          subject.perform(notification_id, temp.id, attempt)
        end.not_to raise_error
      end

      it 'throws an argument error when other params are added' do
        expect do
          subject.perform(notification_id, temp.id, attempt, 'extra_param')
        end.to raise_error(ArgumentError)
      end
    end

    context 'no retry statuses' do
      shared_examples 'does not requeue the job' do |status|
        it "when the status is #{status}" do
          power_of_attorney = ClaimsApi::PowerOfAttorney.find(temp.id)
          allow(ClaimsApi::PowerOfAttorney).to receive(:find).with(temp.id).and_return(power_of_attorney)
          allow(described_class).to receive(:perform_in)
          allow_any_instance_of(described_class).to receive(:notification_response_status).and_return(status)

          expect { subject.perform(notification_id, power_of_attorney.id) }.not_to raise_error

          expect(described_class).not_to have_received(:perform_in)
          process = ClaimsApi::Process.find_by(processable: power_of_attorney, step_type: 'CLAIMANT_NOTIFICATION')
          expect(process.completed_at).not_to be_nil
        end
      end

      described_class::NON_RETRY_STATUSES.each do |status|
        include_examples 'does not requeue the job', status.to_s
      end
    end

    context 'retry statuses' do
      shared_examples 'requeues the job' do |status|
        it "when the status is #{status}" do
          power_of_attorney = ClaimsApi::PowerOfAttorney.find(temp.id)
          allow(ClaimsApi::PowerOfAttorney).to receive(:find).with(temp.id).and_return(power_of_attorney)
          allow_any_instance_of(described_class).to receive(:notification_response_status).and_return(status)
          allow(described_class).to receive(:perform_in)

          expect { subject.perform(notification_id, power_of_attorney.id, 0) }.not_to raise_error

          expect(described_class).to have_received(:perform_in)
            .with(30.minutes, notification_id, power_of_attorney.id, 1)
          process = ClaimsApi::Process.find_by(processable: power_of_attorney, step_type: 'CLAIMANT_NOTIFICATION')
          expect(process.completed_at).to be_nil
        end
      end

      described_class::RETRY_STATUSES.each do |status|
        include_examples 'requeues the job', status.to_s
      end
    end

    context 'retry attempt max' do
      shared_examples 'does not requeue the job when max attempts is reached' do |status|
        it "when the status is #{status}" do
          power_of_attorney = ClaimsApi::PowerOfAttorney.find(temp.id)
          allow(ClaimsApi::PowerOfAttorney).to receive(:find).with(temp.id).and_return(power_of_attorney)
          allow_any_instance_of(described_class).to receive(:notification_response_status).and_return(status)
          allow(described_class).to receive(:perform_in)
          expect_any_instance_of(described_class).to receive(:alert_max_attempts_reached)
            .with("Status for notification #{notification_id} was '#{status}'. POA ID: #{power_of_attorney.id}")

          expect do
            subject.perform(notification_id, power_of_attorney.id, described_class::RETRY_ATTEMPT_MAX)
          end.not_to raise_error

          expect(described_class).not_to have_received(:perform_in)
          process = ClaimsApi::Process.find_by(processable: power_of_attorney, step_type: 'CLAIMANT_NOTIFICATION')
          expect(process.completed_at).not_to be_nil
          expect(process.step_status).to eq('FAILED')
          expect(process.error_messages).to include('Max polling attempts reached')
        end
      end

      described_class::RETRY_STATUSES.each do |status|
        include_examples 'does not requeue the job when max attempts is reached', status.to_s
      end
    end

    context 'retry attempt boundary' do
      shared_examples 'requeues the job at RETRY_ATTEMPT_MAX - 1' do |status|
        it "when the status is #{status}" do
          power_of_attorney = ClaimsApi::PowerOfAttorney.find(temp.id)
          allow(ClaimsApi::PowerOfAttorney).to receive(:find).with(temp.id).and_return(power_of_attorney)
          allow_any_instance_of(described_class).to receive(:notification_response_status).and_return(status)
          allow(described_class).to receive(:perform_in)

          subject.perform(notification_id, power_of_attorney.id, described_class::RETRY_ATTEMPT_MAX - 1)

          expect(described_class).to have_received(:perform_in)
            .with(30.minutes, notification_id, power_of_attorney.id, described_class::RETRY_ATTEMPT_MAX)
        end
      end

      described_class::RETRY_STATUSES.each do |status|
        include_examples 'requeues the job at RETRY_ATTEMPT_MAX - 1', status.to_s
      end
    end

    context 'permanent-failure handling' do
      it 'calls handle_failure and sends a slack alert' do
        power_of_attorney = ClaimsApi::PowerOfAttorney.find(temp.id)
        allow(ClaimsApi::PowerOfAttorney).to receive(:find).with(temp.id).and_return(power_of_attorney)
        allow_any_instance_of(described_class).to receive(:notification_response_status).and_return('permanent-failure')
        allow(described_class).to receive(:perform_in)
        # Override the outer before stub so handle_failure runs and calls slack_alert_on_failure
        allow_any_instance_of(described_class).to receive(:handle_failure).and_call_original
        expect(ClaimsApi::Logger).to receive(:log).with(described_class::LOG_TAG, hash_including(:message))
        expect_any_instance_of(described_class).to receive(:slack_alert_on_failure)

        subject.perform(notification_id, power_of_attorney.id)
      end
    end

    context 'exception handling' do
      it 'logs and re-raises on unexpected errors' do
        allow_any_instance_of(described_class).to receive(:notification_response_status)
          .and_raise(StandardError, 'connection refused')
        expect(ClaimsApi::Logger).to receive(:log).with('va_follow_up_job', hash_including(:message))

        expect { subject.perform(notification_id) }.to raise_error(StandardError, 'connection refused')
      end
    end

    context 'without poa_id' do
      it 'requeues but does not update a process step' do
        allow_any_instance_of(described_class).to receive(:notification_response_status).and_return('pending')
        allow(described_class).to receive(:perform_in)

        expect_any_instance_of(described_class).not_to receive(:update_poa_process_step)
        subject.perform(notification_id, nil, 0)

        expect(described_class).to have_received(:perform_in)
          .with(30.minutes, notification_id, nil, 1)
      end
    end
  end

  describe '#settings' do
    context 'when claims_api_vanotify_service_migration is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:claims_api_vanotify_service_migration).and_return(true)
      end

      it 'returns the new settings path' do
        result = subject.send(:settings)
        expect(result).to eq(Settings.vanotify.services.lighthouse_benefits_claims)
      end
    end

    context 'when claims_api_vanotify_service_migration is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:claims_api_vanotify_service_migration).and_return(false)
      end

      it 'returns the legacy settings path' do
        result = subject.send(:settings)
        expect(result).to eq(Settings.claims_api.vanotify.services.lighthouse)
      end
    end
  end
end
