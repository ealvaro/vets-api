# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/job_tracker'
require 'claims_api/job_tracker_middleware'

RSpec.describe ClaimsApi::JobTrackerMiddleware do
  subject(:middleware) { described_class.new }

  let(:jid) { 'middleware-test-jid' }
  let(:job) { { 'jid' => jid, 'class' => 'ClaimsApi::PoaUpdater', 'args' => ['claim-123'] } }
  let(:non_claims_job) { { 'jid' => 'other-jid', 'class' => 'SomeOtherModule::SomeJob', 'args' => [] } }
  let(:queue) { 'default' }
  let(:redis_key) { ClaimsApi::JobTracker::REDIS_KEY }

  let(:worker) do
    instance_double(ClaimsApi::PoaUpdater).tap do |w|
      allow(w).to receive(:class).and_return(ClaimsApi::PoaUpdater)
    end
  end

  let(:non_claims_worker) do
    double('SomeOtherJob').tap do |w|
      klass = Class.new { define_method(:name) { 'SomeOtherModule::SomeJob' } }
      allow(w).to receive(:class).and_return(klass.new)
    end
  end

  before do
    allow(Flipper).to receive(:enabled?).with(:claims_api_job_tracker).and_return(true)
  end

  after do
    Sidekiq.redis { |conn| conn.hdel(redis_key, jid) }
  end

  describe 'scoping' do
    it 'tracks ClaimsApi jobs' do
      middleware.call(worker, job, queue) { nil }
      # Field was created then deleted on success
      expect(Sidekiq.redis { |conn| conn.hexists(redis_key, jid) }).to eq(0)
    end

    it 'passes through non-ClaimsApi jobs without tracking' do
      expect(ClaimsApi::JobTracker).not_to receive(:track)
      middleware.call(non_claims_worker, non_claims_job, queue) { nil }
    end
  end

  describe 'Flipper control' do
    context 'when flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:claims_api_job_tracker).and_return(false)
      end

      it 'does not track the job' do
        expect(ClaimsApi::JobTracker).not_to receive(:track)
        middleware.call(worker, job, queue) { nil }
      end

      it 'still yields and runs the job' do
        block_called = false
        middleware.call(worker, job, queue) { block_called = true }
        expect(block_called).to be true
      end
    end
  end

  describe 'job lifecycle' do
    it 'tracks the job during execution and cleans up after' do
      middleware.call(worker, job, queue) do
        raw = Sidekiq.redis { |conn| conn.hget(redis_key, jid) }
        data = JSON.parse(raw)
        expect(data['jid']).to eq(jid)
        expect(data['class']).to eq('ClaimsApi::PoaUpdater')
        expect(data['args']).to eq(['claim-123'])
        expect(data['process_identity']).to be_present
      end

      expect(Sidekiq.redis { |conn| conn.hexists(redis_key, jid) }).to eq(0)
    end

    it 'deletes the field on failure and re-raises' do
      expect do
        middleware.call(worker, job, queue) { raise StandardError, 'boom' }
      end.to raise_error(StandardError, 'boom')

      expect(Sidekiq.redis { |conn| conn.hexists(redis_key, jid) }).to eq(0)
    end
  end

  describe 'tracking failure resilience' do
    before do
      allow(ClaimsApi::JobTracker).to receive(:track).and_raise(Redis::ConnectionError, 'Redis down')
    end

    it 'still yields and runs the job' do
      block_called = false
      middleware.call(worker, job, queue) { block_called = true }
      expect(block_called).to be true
    end

    it 'logs a warning' do
      expect(ClaimsApi::Logger).to receive(:log).with(
        'job_tracker_middleware',
        hash_including(level: :warn)
      )
      middleware.call(worker, job, queue) { nil }
    end

    it 'does not attempt to remove a key that was never created' do
      expect(ClaimsApi::JobTracker).not_to receive(:remove)
      middleware.call(worker, job, queue) { nil }
    end
  end
end
