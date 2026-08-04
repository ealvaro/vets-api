# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Search::ResultsCachePurgeJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

  around do |example|
    original_store = Rails.cache
    Rails.cache = memory_store
    example.run
  ensure
    Rails.cache = original_store
  end

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
  end

  describe '#perform' do
    context 'when the :search_results_cache_purge flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:search_results_cache_purge).and_return(true)
      end

      it 'writes a timestamp to the generation key' do
        freeze_time do
          expected_generation = Time.current.to_i

          described_class.new.perform

          written = Rails.cache.read(V0::SearchController::SEARCH_CACHE_GENERATION_KEY)
          expect(written).to eq(expected_generation)
        end
      end

      it 'emits a success increment metric' do
        allow(StatsD).to receive(:increment)
        allow(StatsD).to receive(:gauge)

        described_class.new.perform

        expect(StatsD).to have_received(:increment).with('api.search.results_cache_purge.success')
      end

      it 'emits a generation gauge metric' do
        allow(StatsD).to receive(:increment)
        allow(StatsD).to receive(:gauge)

        freeze_time do
          expected_generation = Time.current.to_i

          described_class.new.perform

          expect(StatsD).to have_received(:gauge).with('api.search.results_cache_purge.generation', expected_generation)
        end
      end
    end

    context 'when the :search_results_cache_purge flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:search_results_cache_purge).and_return(false)
      end

      it 'does not write to the generation key' do
        described_class.new.perform

        written = Rails.cache.read(V0::SearchController::SEARCH_CACHE_GENERATION_KEY)
        expect(written).to be_nil
      end

      it 'does not emit a success metric' do
        allow(StatsD).to receive(:increment)
        allow(StatsD).to receive(:gauge)

        described_class.new.perform

        expect(StatsD).not_to have_received(:increment).with('api.search.results_cache_purge.success')
        expect(StatsD).not_to have_received(:gauge)
      end
    end

    context 'when Rails.cache.write raises an error' do
      before do
        allow(Flipper).to receive(:enabled?).with(:search_results_cache_purge).and_return(true)
        allow(Rails.cache).to receive(:write).and_raise(Redis::CannotConnectError, 'connection refused')
      end

      it 'increments the error metric and re-raises' do
        allow(StatsD).to receive(:increment)

        expect { described_class.new.perform }.to raise_error(Redis::CannotConnectError)

        expect(StatsD).to have_received(:increment).with('api.search.results_cache_purge.error')
      end

      it 'does not emit a success metric' do
        allow(StatsD).to receive(:increment)

        expect { described_class.new.perform }.to raise_error(Redis::CannotConnectError)
        expect(StatsD).not_to have_received(:increment).with('api.search.results_cache_purge.success')
      end
    end
  end
end
