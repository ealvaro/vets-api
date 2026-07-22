# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::JobTrackerRecoveryJob, type: :job do
  subject { described_class.new }

  describe '#perform' do
    context 'when Flipper flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:claims_api_job_tracker).and_return(true)
      end

      it 'calls recover_orphans!' do
        expect(ClaimsApi::JobTracker).to receive(:recover_orphans!).and_return(0)
        subject.perform
      end

      it 'logs when orphans are found' do
        allow(ClaimsApi::JobTracker).to receive(:recover_orphans!).and_return(3)
        expect(ClaimsApi::Logger).to receive(:log).with(
          'job_tracker_recovery',
          hash_including(message: '3 orphaned jobs found')
        )
        subject.perform
      end

      it 'does not log when no orphans are found' do
        allow(ClaimsApi::JobTracker).to receive(:recover_orphans!).and_return(0)
        expect(ClaimsApi::Logger).not_to receive(:log)
        subject.perform
      end
    end

    context 'when Flipper flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:claims_api_job_tracker).and_return(false)
      end

      it 'does not call recover_orphans!' do
        expect(ClaimsApi::JobTracker).not_to receive(:recover_orphans!)
        subject.perform
      end
    end
  end

  describe 'sidekiq_options' do
    it 'does not retry on failure' do
      expect(described_class.sidekiq_options['retry']).to be false
    end
  end
end
