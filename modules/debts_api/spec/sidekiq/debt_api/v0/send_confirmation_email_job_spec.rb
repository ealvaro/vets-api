# frozen_string_literal: true

# Callers always pass exactly one of user_pii or cache_key (mutually exclusive).
# - user_pii: plain or encrypted PII passed directly (e.g. digital dispute success email).
# - cache_key: key for Sidekiq::AttrPackage where PII was stored (e.g. FSR retries).

require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe DebtsApi::V0::Form5655::SendConfirmationEmailJob, type: :worker do
  describe '#perform' do
    let(:user) { create(:user, :loa3) }
    let(:input_cache_key) { 'input_cache_key_123' }
    let(:cached_pii) { { email: user.email, first_name: user.first_name } }
    let(:submission_attrs) { { user_uuid: user.uuid, user_account: user.user_account, state: 1 } }
    let(:fsr_template_id) { DebtsApi::V0::FinancialStatusReportService::IN_PROGRESS_TEMPLATE_ID }
    let(:digital_dispute_template_id) { DebtsApi::V0::DigitalDisputeSubmission::CONFIRMATION_TEMPLATE }

    before do
      allow(Sidekiq::AttrPackage).to receive(:find).with(input_cache_key).and_return(cached_pii)
      allow(Sidekiq::AttrPackage).to receive(:delete)
      allow(Sidekiq::AttrPackage).to receive(:create).and_return('vanotify_cache_key')
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

    # --- Path 1: job has user_pii only (no cache_key) ---
    context 'when job has user_pii only (no cache_key)' do
      let(:lockbox) { DebtsApi::V0::DigitalDisputeSubmission::LOCKBOX }
      let!(:form_submission) do
        create(:debts_api_form5655_submission, **submission_attrs.merge(state: :submitted))
      end
      let(:job_params) do
        {
          'user_uuid' => user.uuid,
          'user_pii' => {
            email: lockbox.encrypt(user.email),
            first_name: lockbox.encrypt(user.first_name)
          },
          'template_id' => fsr_template_id
        }
      end

      it 'does not use cache (no AttrPackage.find or create)' do
        expect(Sidekiq::AttrPackage).not_to receive(:find)
        expect(Sidekiq::AttrPackage).not_to receive(:create)
        described_class.new.perform(job_params)
      end

      it 'passes encrypted user_pii through to VANotifyEmailJob so it can decrypt (e.g. digital dispute flow)' do
        expect(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async).with(
          anything,
          job_params['template_id'],
          anything,
          {}
        ) do |identifier, _template_id, personalisation, _options|
          expect(identifier).to eq(job_params['user_pii'][:email])
          expect(lockbox.decrypt(identifier)).to eq(user.email)
          expect(personalisation['first_name']).to eq(job_params['user_pii'][:first_name])
          expect(lockbox.decrypt(personalisation['first_name'])).to eq(user.first_name)
        end
        described_class.new.perform(job_params)
      end

      it 'still passes ciphertext as identifier after a Sidekiq-like JSON round-trip (string keys in user_pii)' do
        round_tripped = JSON.parse(job_params.to_json)
        expect(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async) do |identifier, *_|
          expect(identifier).to eq(round_tripped['user_pii']['email'])
        end
        described_class.new.perform(round_tripped)
      end
    end

    # --- Path 2: job has cache_key only (no user_pii) ---
    context 'when job has cache_key only (no user_pii)' do
      let(:job_params_with_cache) do
        { 'cache_key' => input_cache_key, 'user_uuid' => user.uuid, 'template_id' => fsr_template_id }
      end

      let(:digital_dispute_job_params_with_cache) do
        {
          'submission_type' => 'digital_dispute',
          'cache_key' => input_cache_key,
          'user_uuid' => user.uuid,
          'template_id' => digital_dispute_template_id
        }
      end

      shared_examples 'sends email using PII from cache' do
        it 'fetches PII from cache and does not pass email as identifier (cache path uses cache_key only)' do
          expect(Sidekiq::AttrPackage).to receive(:find).with(input_cache_key).and_return(cached_pii)
          expect(Sidekiq::AttrPackage).not_to receive(:create)
          expect(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async).with(
            nil,
            job_params['template_id'],
            hash_including('first_name' => user.first_name),
            { id_type: 'email', cache_key: input_cache_key }
          )
          described_class.new.perform(job_params)
        end
      end

      context 'with FSR submission type' do
        context 'when submissions are found' do
          let!(:form_submission) do
            create(:debts_api_form5655_submission, **submission_attrs.merge(state: :submitted))
          end
          let(:job_params) { job_params_with_cache }

          include_examples 'sends email using PII from cache'
        end

        context 'when only in-progress submissions are found' do
          let!(:form_submission) do
            create(:debts_api_form5655_submission, **submission_attrs.merge(state: :in_progress))
          end
          let(:job_params) { job_params_with_cache }

          include_examples 'logs no submissions warning', 'fsr'
        end

        context 'when no submissions are found' do
          let(:job_params) { job_params_with_cache }

          include_examples 'logs no submissions warning', 'fsr'

          it 'deletes the cache_key' do
            allow(Rails.logger).to receive(:warn)
            expect(Sidekiq::AttrPackage).to receive(:delete).with(input_cache_key)
            described_class.new.perform(job_params)
          end
        end

        context 'when an error occurs' do
          let!(:form_submission) do
            create(:debts_api_form5655_submission, **submission_attrs.merge(state: :submitted))
          end
          let(:job_params) { job_params_with_cache }

          it 'raises and logs the error' do
            allow(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async).and_raise(StandardError,
                                                                                               'Test error')
            expect(Rails.logger).to receive(:error).with(
              'DebtsApi::SendConfirmationEmailJob (fsr) - Error sending email: Test error'
            )
            expect { described_class.new.perform(job_params) }.to raise_error(StandardError, 'Test error')
          end

          it 'converts AttrPackageError to ArgumentError to prevent retries' do
            allow(Sidekiq::AttrPackage).to receive(:find).and_raise(
              Sidekiq::AttrPackageError.new('find', 'Redis connection failed')
            )
            expect { described_class.new.perform(job_params) }.to raise_error(ArgumentError, /AttrPackage.*error/)
          end
        end
      end

      context 'with digital dispute submission type' do
        context 'when digital dispute submission is found' do
          let!(:digital_dispute_submission) { create(:debts_api_digital_dispute_submission, **submission_attrs) }
          let(:job_params) { digital_dispute_job_params_with_cache }

          include_examples 'sends email using PII from cache'
        end

        context 'when no digital dispute submissions are found' do
          let(:job_params) { digital_dispute_job_params_with_cache }

          include_examples 'logs no submissions warning', 'digital_dispute'
        end

        context 'PII from AttrPackage' do
          let!(:digital_dispute_submission) { create(:debts_api_digital_dispute_submission, **submission_attrs) }
          let(:job_params) { digital_dispute_job_params_with_cache }

          it 'retrieves PII from cache' do
            allow(DebtManagementCenter::VANotifyEmailJob).to receive(:perform_async)
            expect(Sidekiq::AttrPackage).to receive(:find).with(input_cache_key)
            described_class.new.perform(job_params)
          end
        end
      end
    end
  end

  describe 'sidekiq_retries_exhausted' do
    let(:exception) do
      e = StandardError.new('Test error')
      allow(e).to receive(:backtrace).and_return(['line 1', 'line 2'])
      e
    end

    it 'deletes redis cache_key when retries expire' do
      cache_key = 'test_cache_key_456'
      job = { 'args' => [{ 'cache_key' => cache_key, 'submission_type' => 'fsr', 'user_uuid' => 'test-uuid' }] }

      expect(Sidekiq::AttrPackage).to receive(:delete).with(cache_key)
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:error)

      described_class.sidekiq_retries_exhausted_block.call(job, exception)
    end
  end
end
