# frozen_string_literal: true

require 'rails_helper'

require 'sidekiq/testing'

RSpec.describe DebtsApi::V0::Form5655::VHA::VBSSubmissionJob, type: :worker do
  describe '#perform' do
    let!(:form_submission) do
      create(
        :debts_api_form5655_submission,
        ipf_data: {
          'personal_data' => {
            'email_address' => 'test@test.com',
            'veteran_full_name' => { 'first' => 'John' }
          }
        }.to_json
      )
    end

    it 'submits to VBS with the persisted submission and no user cache' do
      service = instance_double(DebtsApi::V0::FinancialStatusReportService)

      expect(UserProfileAttributes).not_to receive(:find)
      expect(DebtsApi::V0::FinancialStatusReportService).to receive(:new).with(no_args).and_return(service)
      expect(service).to receive(:submit_to_vbs).with(form_submission)
      expect(StatsD).to receive(:increment).with("#{described_class::STATS_KEY}.success")

      described_class.new.perform(form_submission.id)
    end

    context 'when all retries are exhausted' do
      let(:config) { described_class }
      let(:standard_exception) do
        e = StandardError.new('abc-123')
        allow(e).to receive(:backtrace).and_return(%w[backtrace1 backtrace2])
        e
      end
      let(:msg) do
        {
          'class' => 'YourJobClassName',
          'args' => [form_submission.id],
          'jid' => '12345abcde',
          'retry_count' => 5
        }
      end

      before do
        allow(DebtsApi::V0::Form5655Submission).to receive(:find).and_return(form_submission)
        allow(Flipper).to receive(:enabled?).and_return(false)
      end

      it 'increments the retries exhausted counter and logs error information' do
        statsd_key = DebtsApi::V0::Form5655::VHA::VBSSubmissionJob::STATS_KEY

        [
          "#{statsd_key}.failure",
          "#{statsd_key}.retries_exhausted",
          'api.fsr_submission.failure',
          'api.fsr_submission.send_failed_form_email.enqueue',
          'shared.sidekiq.default.DebtManagementCenter_VANotifyEmailJob.enqueue'
        ].each do |key|
          if key == 'api.fsr_submission.failure'
            expect(StatsD).to receive(:increment).with(key, hash_including(tags: kind_of(Array)))
          else
            expect(StatsD).to receive(:increment).with(key)
          end
        end

        expect(Rails.logger).to receive(:error).with(
          "Form5655Submission id: #{form_submission.id} failed", 'VBS Submission Failed: abc-123'
        )

        expect(Rails.logger).to receive(:error).with(
          'V0::Form5655::VHA::VBSSubmissionJob retries exhausted',
          submission_id: form_submission.id, user_id: form_submission.user_uuid, exception: standard_exception
        )
        config.sidekiq_retries_exhausted_block.call(msg, standard_exception)
        expect(form_submission.reload.error_message).to eq('VBS Submission Failed: abc-123')
      end
    end
  end
end
