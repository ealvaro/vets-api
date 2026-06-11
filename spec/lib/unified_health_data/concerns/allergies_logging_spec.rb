# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/concerns/allergies_logging'
require 'unified_health_data/constants'
require 'medical_records/medical_records_log'

RSpec.describe UnifiedHealthData::Concerns::AllergiesLogging do
  subject(:instance) { test_class.new(user) }

  let(:user) { build(:user, :loa3) }

  let(:test_class) do
    klass = Class.new do
      include UnifiedHealthData::Concerns::AllergiesLogging

      def initialize(user)
        @user = user
      end
    end
    klass.const_set(:STATSD_KEY_PREFIX, 'api.uhd')
    klass
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:gauge)
    allow(StatsD).to receive(:increment)
  end

  describe '#allergies_logging_enabled?' do
    it 'returns true when the domain toggle is enabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(true)

      expect(instance.send(:allergies_logging_enabled?)).to be true
    end

    it 'returns true when the global toggle is enabled as fallback' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(true)

      expect(instance.send(:allergies_logging_enabled?)).to be true
    end

    it 'returns false when both toggles are disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      expect(instance.send(:allergies_logging_enabled?)).to be false
    end
  end

  describe '#log_allergies_response_count' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(true)
    end

    it 'logs the total, returned, and filtered counts' do
      instance.send(:log_allergies_response_count, 10, 7)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'allergies',
          action: 'filter',
          total_entries: 10,
          returned: 7,
          filtered: 3,
          log_level_context: 'diagnostic'
        )
      )
    end
  end

  describe '#log_allergies_index_metrics' do
    let(:combined_records) do
      [
        { 'source' => 'vista', 'resource' => {} },
        { 'source' => 'vista', 'resource' => {} },
        { 'source' => 'oracle-health', 'resource' => {} }
      ]
    end

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(true)
    end

    it 'logs the source breakdown' do
      instance.send(:log_allergies_index_metrics, combined_records, 3)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'allergies',
          action: 'index',
          total_allergies: 3,
          vista_raw: 2,
          oracle_health_raw: 1,
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'emits StatsD gauges for each source' do
      instance.send(:log_allergies_index_metrics, combined_records, 3)

      expect(StatsD).to have_received(:gauge).with('api.uhd.allergies.index.total', 3)
      expect(StatsD).to have_received(:gauge).with('api.uhd.allergies.index.vista', 2)
      expect(StatsD).to have_received(:gauge).with('api.uhd.allergies.index.oracle_health', 1)
    end
  end

  describe '#warn_allergies_high_filter_rate' do
    it 'warns when more than 50% of records are filtered' do
      instance.send(:warn_allergies_high_filter_rate, 10, 4)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          service: 'medical_records',
          resource: 'allergies',
          action: 'index',
          anomaly: 'high_filter_rate',
          filter_rate: 60.0,
          raw_count: 10,
          returned_count: 4
        )
      )
    end

    it 'emits a StatsD increment for the anomaly' do
      instance.send(:warn_allergies_high_filter_rate, 10, 4)

      expect(StatsD).to have_received(:increment)
        .with('api.uhd.allergies.anomaly.high_filter_rate')
    end

    it 'includes source_breakdown when high filter rate triggers' do
      instance.send(:warn_allergies_high_filter_rate, 10, 4, source_breakdown: { vista_raw: 6, oracle_health_raw: 4 })

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          anomaly: 'high_filter_rate',
          vista_raw: 6,
          oracle_health_raw: 4
        )
      )
    end

    it 'does not warn when filter rate is at or below 50%' do
      instance.send(:warn_allergies_high_filter_rate, 10, 5)

      expect(Rails.logger).not_to have_received(:warn)
      expect(StatsD).not_to have_received(:increment)
        .with('api.uhd.allergies.anomaly.high_filter_rate')
    end

    it 'does not warn when raw_count is zero' do
      instance.send(:warn_allergies_high_filter_rate, 0, 0)

      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  describe '#warn_allergies_duplicate_ids' do
    it 'warns and increments StatsD when duplicate IDs exist' do
      parsed = [
        double('Allergy', id: '111'),
        double('Allergy', id: '111'),
        double('Allergy', id: '222')
      ]

      instance.send(:warn_allergies_duplicate_ids, parsed)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          service: 'medical_records',
          resource: 'allergies',
          action: 'index',
          anomaly: 'duplicate_ids',
          duplicate_ids: ['111'],
          duplicate_count: 2,
          total_count: 3
        )
      )
      expect(StatsD).to have_received(:increment)
        .with('api.uhd.allergies.anomaly.duplicate_ids')
    end

    it 'reports multiple duplicate IDs' do
      parsed = [
        double('Allergy', id: '111'),
        double('Allergy', id: '111'),
        double('Allergy', id: '222'),
        double('Allergy', id: '222'),
        double('Allergy', id: '333')
      ]

      instance.send(:warn_allergies_duplicate_ids, parsed)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          duplicate_ids: %w[111 222],
          duplicate_count: 4,
          total_count: 5
        )
      )
    end

    it 'does not warn when all IDs are unique' do
      parsed = [
        double('Allergy', id: '111'),
        double('Allergy', id: '222')
      ]

      instance.send(:warn_allergies_duplicate_ids, parsed)

      expect(Rails.logger).not_to have_received(:warn)
      expect(StatsD).not_to have_received(:increment)
        .with('api.uhd.allergies.anomaly.duplicate_ids')
    end

    it 'does not warn when parsed_allergies is empty' do
      instance.send(:warn_allergies_duplicate_ids, [])

      expect(Rails.logger).not_to have_received(:warn)
      expect(StatsD).not_to have_received(:increment)
        .with('api.uhd.allergies.anomaly.duplicate_ids')
    end
  end

  describe '#log_allergies_metrics' do
    let(:combined_records) do
      [
        { 'source' => 'vista', 'resource' => {} },
        { 'source' => 'oracle-health', 'resource' => {} }
      ]
    end
    let(:parsed_allergies) { [double('Allergy', id: '123')] }

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(true)
    end

    it 'calls response count, index metrics, and high filter rate warning' do
      instance.send(:log_allergies_metrics, combined_records, parsed_allergies)

      expect(Rails.logger).to have_received(:info).at_least(:once)
      expect(StatsD).to have_received(:gauge).at_least(:once)
    end

    it 'calls duplicate ID warning' do
      dupes = [double('Allergy', id: '111'), double('Allergy', id: '111')]

      instance.send(:log_allergies_metrics, combined_records, dupes)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(anomaly: 'duplicate_ids', duplicate_ids: ['111'])
      )
    end

    it 'skips diagnostic logs when toggle is disabled but still warns on high filter rate' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      instance.send(:log_allergies_metrics, combined_records, [])

      # Always-on warning still fires with source_breakdown
      expect(Rails.logger).to have_received(:warn).with(
        hash_including(anomaly: 'high_filter_rate', vista_raw: 1, oracle_health_raw: 1)
      )
    end
  end

  describe '#log_allergies_raw_source_counts' do
    let(:body) do
      {
        'vista' => { 'entry' => [{ 'resource' => {} }, { 'resource' => {} }] },
        'oracle-health' => { 'entry' => [{ 'resource' => {} }] }
      }
    end

    it 'logs raw entry counts when toggle is enabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(true)

      instance.send(:log_allergies_raw_source_counts, body)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          resource: 'allergies',
          action: 'index',
          stage: 'raw_from_scdf',
          vista_entry_count: 2,
          oracle_health_entry_count: 1,
          total_entry_count: 3,
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'does not log when toggle is disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      instance.send(:log_allergies_raw_source_counts, body)

      expect(Rails.logger).not_to have_received(:info)
    end
  end

  describe '#log_allergies_error' do
    let(:error) { Faraday::TimeoutError.new('connection timed out') }

    it 'logs the error with domain context' do
      allow(Rails.logger).to receive(:error)

      instance.send(:log_allergies_error, error)

      expect(Rails.logger).to have_received(:error).with(
        hash_including(
          service: 'medical_records',
          resource: 'allergies',
          action: 'index',
          error_class: 'Faraday::TimeoutError',
          error_message: 'connection timed out'
        )
      )
    end

    it 'increments StatsD error counter' do
      allow(Rails.logger).to receive(:error)

      instance.send(:log_allergies_error, error)

      expect(StatsD).to have_received(:increment).with('api.uhd.allergies.error')
    end
  end
end
