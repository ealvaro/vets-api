# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe DebtsApi::V0::Form5655::SendConfirmationEmailJob, type: :worker do
  describe '#perform' do
    let(:user) { create(:user, :loa3) }
    let(:lockbox) { Lockbox.new(key: Settings.lockbox.master_key, encode: true) }
    let(:submission_attrs) { { user_uuid: user.uuid, user_account: user.user_account, state: 1 } }
    let(:fsr_template_id) { DebtsApi::V0::FinancialStatusReportService::IN_PROGRESS_TEMPLATE_ID }
    let(:digital_dispute_template_id) { DebtsApi::V0::DigitalDisputeSubmission::CONFIRMATION_TEMPLATE }
    let(:user_pii) do
      {
        email: lockbox.encrypt(user.email),
        first_name: lockbox.encrypt(user.first_name)
      }
    end

    it 'raises for an unknown submission_type' do
      job_params = { 'submission_type' => 'banana', 'user_uuid' => user.uuid, 'template_id' => fsr_template_id }

      expect(DebtManagementCenter::VANotifyEmailJob).not_to receive(:perform_async)
      expect { described_class.new.perform(job_params) }.to raise_error(KeyError)
    end

    shared_examples 'logs no submissions warning' do |submission_type|
      it "logs a warning message#{submission_type == 'digital_dispute' ? ' for digital dispute' : ''}" do
        expect(Rails.logger).to receive(:warn).with(
          "DebtsApi::SendConfirmationEmailJob (#{submission_type}) - " \
          "No submissions found for user_uuid: #{job_params['user_uuid']}"
        )
        described_class.new.perform(job_params)
      end
    end

    context 'with FSR submission type' do
      let(:job_params) do
        {
          'user_uuid' => user.uuid,
          'user_pii' => user_pii,
          'template_id' => fsr_template_id
        }
      end

      context 'when submissions are found' do
        let!(:form_submission) do
          create(:debts_api_form5655_submission, **submission_attrs.merge(state: :submitted))
        end

        it 'passes encrypted user PII through to VANotifyEmailJob' do
          expect(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async).with(
            user_pii[:email],
            job_params['template_id'],
            hash_including('first_name' => user_pii[:first_name]),
            {}
          )
          described_class.new.perform(job_params)
        end

        it 'still passes ciphertext after a Sidekiq-like JSON round-trip' do
          round_tripped = JSON.parse(job_params.to_json)
          expect(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async) do |identifier, _template_id,
                                                                                        personalisation, _options|
            expect(identifier).to eq(round_tripped['user_pii']['email'])
            expect(personalisation['first_name']).to eq(round_tripped['user_pii']['first_name'])
          end
          described_class.new.perform(round_tripped)
        end

        it 'increments the FSR confirmation email sent counter' do
          allow(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async)

          expect(StatsD).to receive(:increment).with('api.form5655.send_confirmation_email.sent')

          described_class.new.perform(job_params)
        end

        it 'does not enqueue VANotifyEmailJob when email is missing' do
          job_params['user_pii'] = user_pii.except(:email)

          expect(Rails.logger).to receive(:warn).with(
            "DebtsApi::SendConfirmationEmailJob (fsr) - No email found for user_uuid: #{user.uuid}"
          )
          expect(DebtManagementCenter::VANotifyEmailJob).not_to receive(:perform_async)

          described_class.new.perform(job_params)
        end
      end

      context 'when only in-progress submissions are found' do
        let!(:form_submission) do
          create(:debts_api_form5655_submission, **submission_attrs.merge(state: :in_progress))
        end

        include_examples 'logs no submissions warning', 'fsr'
      end

      context 'when no submissions are found' do
        include_examples 'logs no submissions warning', 'fsr'
      end

      context 'when an error occurs' do
        let!(:form_submission) do
          create(:debts_api_form5655_submission, **submission_attrs.merge(state: :submitted))
        end

        it 'raises and logs the error' do
          allow(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async).and_raise(StandardError,
                                                                                             'Test error')
          expect(Rails.logger).to receive(:error).with(
            'DebtsApi::SendConfirmationEmailJob (fsr) - Error sending email: Test error'
          )
          expect { described_class.new.perform(job_params) }.to raise_error(StandardError, 'Test error')
        end
      end
    end

    context 'with digital dispute submission type' do
      let(:job_params) do
        {
          'submission_type' => 'digital_dispute',
          'user_uuid' => user.uuid,
          'user_pii' => user_pii,
          'template_id' => digital_dispute_template_id
        }
      end

      context 'when digital dispute submission is found' do
        let!(:digital_dispute_submission) { create(:debts_api_digital_dispute_submission, **submission_attrs) }

        it 'passes encrypted user PII through to VANotifyEmailJob' do
          expect(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async).with(
            user_pii[:email],
            job_params['template_id'],
            hash_including('first_name' => user_pii[:first_name]),
            {}
          )
          described_class.new.perform(job_params)
        end

        it 'increments the Digital Dispute confirmation email sent counter' do
          allow(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async)

          expect(StatsD).to receive(:increment).with('api.digital_dispute.send_confirmation_email.sent')

          described_class.new.perform(job_params)
        end
      end

      context 'when no digital dispute submissions are found' do
        include_examples 'logs no submissions warning', 'digital_dispute'
      end
    end
  end

  describe 'sidekiq_retries_exhausted' do
    let(:exception) do
      e = StandardError.new('Test error')
      allow(e).to receive(:backtrace).and_return(['line 1', 'line 2'])
      e
    end

    it 'increments retries exhausted and logs without cache cleanup' do
      job = { 'args' => [{ 'submission_type' => 'fsr', 'user_uuid' => 'test-uuid' }] }

      expect(StatsD).to receive(:increment).with('api.form5655.send_confirmation_email.retries_exhausted')
      expect(Rails.logger).to receive(:error).with(
        'V0::Form5655::SendConfirmationEmailJob (fsr) retries exhausted',
        user_id: 'test-uuid',
        exception:
      )

      described_class.sidekiq_retries_exhausted_block.call(job, exception)
    end
  end
end
