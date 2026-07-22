# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/job_tracker'

RSpec.describe ClaimsApi::JobTracker do
  let(:jid) { 'test-jid-123' }
  let(:job_class) { 'ClaimsApi::PoaUpdater' }
  let(:args) { ['claim-id-456'] }
  let(:process_identity) { 'test-host:999:abc123' }
  let(:redis_key) { described_class::REDIS_KEY }

  after do
    Sidekiq.redis { |conn| conn.hdel(redis_key, jid) }
  end

  describe '.track' do
    it 'writes job metadata as a field in the running_jobs hash' do
      described_class.track(jid:, job_class:, args:, process_identity:)

      raw = Sidekiq.redis { |conn| conn.hget(redis_key, jid) }
      data = JSON.parse(raw)
      expect(data['jid']).to eq(jid)
      expect(data['class']).to eq(job_class)
      expect(data['args']).to eq(args)
      expect(data['process_identity']).to eq(process_identity)
      expect(data['started_at']).to be_present
    end

    it 'overwrites safely if the same jid is tracked again' do
      described_class.track(jid:, job_class:, args:, process_identity: 'old-host:1:aaa')
      described_class.track(jid:, job_class:, args:, process_identity: 'new-host:2:bbb')

      data = JSON.parse(Sidekiq.redis { |conn| conn.hget(redis_key, jid) })
      expect(data['process_identity']).to eq('new-host:2:bbb')
    end
  end

  describe '.remove' do
    it 'deletes the field from the running_jobs hash' do
      described_class.track(jid:, job_class:, args:, process_identity:)
      expect(Sidekiq.redis { |conn| conn.hexists(redis_key, jid) }).to eq(1)

      described_class.remove(jid)
      expect(Sidekiq.redis { |conn| conn.hexists(redis_key, jid) }).to eq(0)
    end

    it 'does not error when field does not exist' do
      expect { described_class.remove('nonexistent-jid') }.not_to raise_error
    end
  end

  describe '.recover_orphans!' do
    let(:dead_identity) { 'dead-host:999:deadbeef' }
    let(:alive_identity) { 'alive-host:123:abc123' }

    before do
      Sidekiq.redis { |conn| conn.del(redis_key) }

      process_set = [{ 'identity' => alive_identity }]
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(process_set)
    end

    after do
      Sidekiq.redis { |conn| conn.del(redis_key) }
    end

    context 'when there are orphaned fields from dead processes' do
      before do
        described_class.track(jid: 'orphan-1', job_class:, args:, process_identity: dead_identity)
      end

      it 'deletes the orphaned field' do
        described_class.recover_orphans!
        expect(Sidekiq.redis { |conn| conn.hexists(redis_key, 'orphan-1') }).to eq(0)
      end

      it 'returns the count of orphans found' do
        expect(described_class.recover_orphans!).to eq(1)
      end

      it 'logs the recovery' do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'job_tracker',
          hash_including(detail: 'Orphaned job detected (log only)', jid: 'orphan-1')
        )
        described_class.recover_orphans!
      end

      context 'with log_only: true (default)' do
        it 'does NOT re-enqueue the job' do
          expect(ClaimsApi::PoaUpdater).not_to receive(:perform_async)
          described_class.recover_orphans!
        end
      end

      context 'with log_only: false' do
        it 're-enqueues the job with original arguments' do
          expect(ClaimsApi::PoaUpdater).to receive(:perform_async).with(*args)
          described_class.recover_orphans!(log_only: false)
        end

        it 'logs as recovered' do
          allow(ClaimsApi::PoaUpdater).to receive(:perform_async)
          expect(ClaimsApi::Logger).to receive(:log).with(
            'job_tracker',
            hash_including(detail: 'Recovered orphaned job')
          )
          described_class.recover_orphans!(log_only: false)
        end

        context 'when re-enqueue fails' do
          before do
            allow(ClaimsApi::PoaUpdater).to receive(:perform_async).and_raise(StandardError, 'enqueue failed')
          end

          it 'retains the tracker field for the next recovery attempt' do
            described_class.recover_orphans!(log_only: false)
            expect(Sidekiq.redis { |conn| conn.hexists(redis_key, 'orphan-1') }).to eq(1)
          end

          it 'logs the failure' do
            expect(ClaimsApi::Logger).to receive(:log).with(
              'job_tracker',
              hash_including(level: :error, detail: /Failed to recover/)
            )
            described_class.recover_orphans!(log_only: false)
          end

          it 'does not count it as a recovered orphan' do
            expect(described_class.recover_orphans!(log_only: false)).to eq(0)
          end
        end
      end
    end

    context 'when fields belong to alive processes' do
      before do
        described_class.track(jid: 'alive-job', job_class:, args:, process_identity: alive_identity)
      end

      it 'skips them and returns 0' do
        expect(described_class.recover_orphans!).to eq(0)
      end

      it 'does not delete the field' do
        described_class.recover_orphans!
        expect(Sidekiq.redis { |conn| conn.hexists(redis_key, 'alive-job') }).to eq(1)
      end
    end

    context 'when there are no tracker fields' do
      it 'returns 0' do
        expect(described_class.recover_orphans!).to eq(0)
      end
    end

    context 'with multiple orphans' do
      before do
        described_class.track(jid: 'orphan-a', job_class:, args: ['a'], process_identity: dead_identity)
        described_class.track(jid: 'orphan-b', job_class:, args: ['b'], process_identity: dead_identity)
        described_class.track(jid: 'alive-c', job_class:, args: ['c'], process_identity: alive_identity)
      end

      it 'recovers only orphans and skips alive jobs' do
        expect(described_class.recover_orphans!).to eq(2)
        expect(Sidekiq.redis { |conn| conn.hexists(redis_key, 'alive-c') }).to eq(1)
      end
    end

    context 'when a tracker field contains malformed JSON' do
      before do
        # Write valid orphan
        described_class.track(jid: 'good-orphan', job_class:, args:, process_identity: dead_identity)
        # Write malformed entry directly
        Sidekiq.redis { |conn| conn.hset(redis_key, 'bad-json', '{not valid json') }
      end

      it 'skips the bad entry, deletes it, and continues scanning' do
        expect(described_class.recover_orphans!).to eq(1)
      end

      it 'removes the malformed field from Redis' do
        described_class.recover_orphans!
        expect(Sidekiq.redis { |conn| conn.hexists(redis_key, 'bad-json') }).to eq(0)
      end

      it 'logs a warning for the malformed entry' do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'job_tracker',
          hash_including(level: :warn, detail: /Malformed tracker entry/)
        )
        allow(ClaimsApi::Logger).to receive(:log).with('job_tracker', hash_excluding(level: :warn))
        described_class.recover_orphans!
      end
    end
  end
end
