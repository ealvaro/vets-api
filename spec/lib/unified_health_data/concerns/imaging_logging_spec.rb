# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/concerns/imaging_logging'
require 'unified_health_data/models/imaging_study'
require 'medical_records/medical_records_log'

RSpec.describe UnifiedHealthData::Concerns::ImagingLogging do
  subject(:instance) { test_class.new(user) }

  let(:user) { build(:user, :loa3) }

  # Create a lightweight test class that includes the concern
  let(:test_class) do
    klass = Class.new do
      include UnifiedHealthData::Concerns::ImagingLogging

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
    allow(Rails.logger).to receive(:error)
    allow(StatsD).to receive(:gauge)
    allow(StatsD).to receive(:increment)
  end

  # --- Helpers for building FHIR-like raw entries ---

  def raw_entry(id:, source: 'vista', reason_reference: nil)
    resource = {
      'resourceType' => 'ImagingStudy',
      'id' => id,
      'meta' => {
        'tag' => [{ 'system' => 'http://va.gov/mhv/fhir/tag/source-system', 'code' => source }]
      }
    }
    resource['reasonReference'] = [{ 'reference' => reason_reference }] if reason_reference
    { 'resource' => resource }
  end

  def parsed_study(id:, event_id: nil, description: 'CT CHEST')
    UnifiedHealthData::ImagingStudy.new(
      id:,
      event_id:,
      description:
    )
  end

  describe '#imaging_logging_enabled?' do
    it 'returns true when the domain toggle is enabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(true)

      expect(instance.send(:imaging_logging_enabled?)).to be true
    end

    it 'returns true when the global toggle is enabled as fallback' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(true)

      expect(instance.send(:imaging_logging_enabled?)).to be true
    end

    it 'returns false when both toggles are disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      expect(instance.send(:imaging_logging_enabled?)).to be false
    end
  end

  describe '#extract_source_system' do
    it 'returns vista when meta.tag has vista code' do
      resource = raw_entry(id: '1', source: 'vista')['resource']
      expect(instance.send(:extract_source_system, resource)).to eq('vista')
    end

    it 'returns oracle-health when meta.tag has oracle-health code' do
      resource = raw_entry(id: '1', source: 'oracle-health')['resource']
      expect(instance.send(:extract_source_system, resource)).to eq('oracle-health')
    end

    it 'returns unknown when meta.tag is missing' do
      resource = { 'resourceType' => 'ImagingStudy', 'id' => '1' }
      expect(instance.send(:extract_source_system, resource)).to eq('unknown')
    end

    it 'returns unknown when no source-system tag matches' do
      resource = {
        'resourceType' => 'ImagingStudy',
        'id' => '1',
        'meta' => { 'tag' => [{ 'system' => 'http://other-system', 'code' => 'foo' }] }
      }
      expect(instance.send(:extract_source_system, resource)).to eq('unknown')
    end
  end

  describe '#normalize_study_name' do
    it 'lowercases and strips non-alphanumeric characters' do
      expect(instance.send(:normalize_study_name, 'CT Chest W/Contrast')).to eq('ctchestwcontrast')
    end

    it 'returns nil for blank input' do
      expect(instance.send(:normalize_study_name, nil)).to be_nil
      expect(instance.send(:normalize_study_name, '')).to be_nil
    end
  end

  describe '#log_imaging_raw_entry_metrics' do
    let(:raw_records) do
      [
        raw_entry(id: '1', source: 'vista', reason_reference: 'DiagnosticReport/v-123'),
        raw_entry(id: '2', source: 'vista'),
        raw_entry(id: '3', source: 'oracle-health', reason_reference: 'DiagnosticReport/oh-456'),
        raw_entry(id: '4', source: 'oracle-health', reason_reference: 'DiagnosticReport/oh-789')
      ]
    end

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(true)
    end

    it 'logs raw entry counts with source and event_id breakdown' do
      instance.send(:log_imaging_raw_entry_metrics, raw_records)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'imaging',
          action: 'index',
          stage: 'raw_from_scdf',
          total_imaging_entries: 4,
          with_event_id: 3,
          without_event_id: 1,
          vista_total: 2,
          vista_with_event_id: 1,
          oh_total: 2,
          oh_with_event_id: 2,
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'handles empty records' do
      instance.send(:log_imaging_raw_entry_metrics, [])

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          total_imaging_entries: 0,
          with_event_id: 0,
          without_event_id: 0
        )
      )
    end

    it 'filters out non-ImagingStudy resource types' do
      mixed = [
        raw_entry(id: '1', source: 'vista'),
        { 'resource' => { 'resourceType' => 'DiagnosticReport', 'id' => '99' } }
      ]

      instance.send(:log_imaging_raw_entry_metrics, mixed)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(total_imaging_entries: 1)
      )
    end

    it 'does not log when logging is disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      instance.send(:log_imaging_raw_entry_metrics, raw_records)

      expect(Rails.logger).not_to have_received(:info)
    end
  end

  describe '#log_imaging_parsed_metrics' do
    let(:raw_records) do
      [
        raw_entry(id: 's1', source: 'vista', reason_reference: 'DiagnosticReport/v-1'),
        raw_entry(id: 's2', source: 'oracle-health', reason_reference: 'DiagnosticReport/oh-1'),
        raw_entry(id: 's3', source: 'oracle-health')
      ]
    end

    let(:parsed_studies) do
      [
        parsed_study(id: 's1', event_id: 'v-1', description: 'CT Chest'),
        parsed_study(id: 's2', event_id: 'oh-1', description: 'CT Chest'),
        parsed_study(id: 's3', event_id: nil, description: 'MRI Brain')
      ]
    end

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(true)
    end

    it 'logs parsed study counts with source and event_id breakdown' do
      instance.send(:log_imaging_parsed_metrics, parsed_studies, raw_records)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'imaging',
          action: 'index',
          stage: 'parsed',
          total_parsed: 3,
          with_event_id: 2,
          without_event_id: 1,
          vista_total: 1,
          vista_with_event_id: 1,
          oh_total: 2,
          oh_with_event_id: 1,
          unique_study_name_count: 2,
          duplicate_study_names: true,
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'sets duplicate_study_names to false when all names are unique' do
      unique_studies = [
        parsed_study(id: 's1', description: 'CT Chest'),
        parsed_study(id: 's2', description: 'MRI Brain')
      ]
      unique_raw = [
        raw_entry(id: 's1', source: 'vista'),
        raw_entry(id: 's2', source: 'oracle-health')
      ]

      instance.send(:log_imaging_parsed_metrics, unique_studies, unique_raw)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          unique_study_name_count: 2,
          duplicate_study_names: false
        )
      )
    end

    it 'emits StatsD gauges for total and event_id counts' do
      instance.send(:log_imaging_parsed_metrics, parsed_studies, raw_records)

      expect(StatsD).to have_received(:gauge).with('api.uhd.imaging.index.total', 3)
      expect(StatsD).to have_received(:gauge).with('api.uhd.imaging.index.with_event_id', 2)
      expect(StatsD).to have_received(:gauge).with('api.uhd.imaging.index.without_event_id', 1)
    end

    it 'increments duplicate_study_names StatsD when duplicates exist' do
      instance.send(:log_imaging_parsed_metrics, parsed_studies, raw_records)

      expect(StatsD).to have_received(:increment).with('api.uhd.imaging.index.duplicate_study_names')
    end

    it 'does not increment duplicate_study_names StatsD when all names are unique' do
      unique_studies = [
        parsed_study(id: 's1', description: 'CT Chest'),
        parsed_study(id: 's2', description: 'MRI Brain')
      ]
      unique_raw = [
        raw_entry(id: 's1', source: 'vista'),
        raw_entry(id: 's2', source: 'oracle-health')
      ]

      instance.send(:log_imaging_parsed_metrics, unique_studies, unique_raw)

      expect(StatsD).not_to have_received(:increment)
        .with('api.uhd.imaging.index.duplicate_study_names')
    end

    it 'handles empty parsed studies array' do
      instance.send(:log_imaging_parsed_metrics, [], raw_records)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          total_parsed: 0,
          with_event_id: 0,
          without_event_id: 0,
          unique_study_name_count: 0,
          duplicate_study_names: false
        )
      )
    end

    it 'does not flag duplicates when blank descriptions reduce named_count below total' do
      studies_with_blank = [
        parsed_study(id: 's1', description: 'CT Chest'),
        parsed_study(id: 's2', description: nil)
      ]
      blank_raw = [
        raw_entry(id: 's1', source: 'vista'),
        raw_entry(id: 's2', source: 'oracle-health')
      ]

      instance.send(:log_imaging_parsed_metrics, studies_with_blank, blank_raw)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          unique_study_name_count: 1,
          duplicate_study_names: false
        )
      )
    end

    it 'does not log when logging is disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      instance.send(:log_imaging_parsed_metrics, parsed_studies, raw_records)

      expect(Rails.logger).not_to have_received(:info)
    end
  end

  describe '#log_imaging_metrics' do
    let(:raw_records) do
      [
        raw_entry(id: 's1', source: 'vista', reason_reference: 'DiagnosticReport/v-1'),
        raw_entry(id: 's2', source: 'oracle-health')
      ]
    end

    let(:parsed_studies) do
      [
        parsed_study(id: 's1', event_id: 'v-1', description: 'CT Chest'),
        parsed_study(id: 's2', event_id: nil, description: 'MRI Brain')
      ]
    end

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_imaging_diagnostic, user)
        .and_return(true)
    end

    it 'calls both raw and parsed logging methods' do
      instance.send(:log_imaging_metrics, raw_records, parsed_studies)

      # Raw metrics
      expect(Rails.logger).to have_received(:info).with(
        hash_including(stage: 'raw_from_scdf', total_imaging_entries: 2)
      )

      # Parsed metrics
      expect(Rails.logger).to have_received(:info).with(
        hash_including(stage: 'parsed', total_parsed: 2)
      )
    end
  end

  describe '#log_imaging_error' do
    let(:error) { Faraday::TimeoutError.new('connection timed out') }

    it 'logs an error with domain context' do
      instance.send(:log_imaging_error, error)

      expect(Rails.logger).to have_received(:error).with(
        hash_including(
          service: 'medical_records',
          resource: 'imaging',
          action: 'index',
          error_class: 'Faraday::TimeoutError',
          error_message: 'connection timed out'
        )
      )
    end

    it 'increments the error StatsD counter' do
      instance.send(:log_imaging_error, error)

      expect(StatsD).to have_received(:increment).with('api.uhd.imaging.error')
    end
  end

  describe '#build_source_lookup' do
    it 'maps resource IDs to their source system' do
      records = [
        raw_entry(id: 'a', source: 'vista'),
        raw_entry(id: 'b', source: 'oracle-health')
      ]

      lookup = instance.send(:build_source_lookup, records)

      expect(lookup).to eq('a' => 'vista', 'b' => 'oracle-health')
    end

    it 'skips non-ImagingStudy resources' do
      records = [
        raw_entry(id: 'a', source: 'vista'),
        { 'resource' => { 'resourceType' => 'DiagnosticReport', 'id' => 'dr-1' } }
      ]

      lookup = instance.send(:build_source_lookup, records)

      expect(lookup).to eq('a' => 'vista')
    end

    it 'handles entries without resource wrapper' do
      records = [
        { 'resourceType' => 'ImagingStudy', 'id' => 'x',
          'meta' => { 'tag' => [{ 'system' => 'http://va.gov/mhv/fhir/tag/source-system', 'code' => 'vista' }] } }
      ]

      lookup = instance.send(:build_source_lookup, records)

      expect(lookup).to eq('x' => 'vista')
    end
  end

  describe '#tally_raw_entries' do
    it 'counts source and event_id presence' do
      entries = [
        raw_entry(id: '1', source: 'vista', reason_reference: 'DiagnosticReport/v-1'),
        raw_entry(id: '2', source: 'vista'),
        raw_entry(id: '3', source: 'oracle-health', reason_reference: 'DiagnosticReport/oh-1')
      ]

      tally = instance.send(:tally_raw_entries, entries)

      expect(tally[:source_counts]).to eq('vista' => 2, 'oracle-health' => 1)
      expect(tally[:event_id_by_source]).to eq('vista' => 1, 'oracle-health' => 1)
      expect(tally[:with_event_id]).to eq(2)
    end
  end

  describe '#tally_parsed_studies' do
    it 'counts source, event_id presence, and unique names' do
      source_by_id = { 's1' => 'vista', 's2' => 'oracle-health', 's3' => 'oracle-health' }
      studies = [
        parsed_study(id: 's1', event_id: 'v-1', description: 'CT Chest'),
        parsed_study(id: 's2', event_id: 'oh-1', description: 'CT Chest'),
        parsed_study(id: 's3', event_id: nil, description: 'MRI Brain')
      ]

      tally = instance.send(:tally_parsed_studies, studies, source_by_id)

      expect(tally[:source_counts]).to eq('vista' => 1, 'oracle-health' => 2)
      expect(tally[:event_id_by_source]).to eq('vista' => 1, 'oracle-health' => 1)
      expect(tally[:with_event_id]).to eq(2)
      expect(tally[:unique_name_count]).to eq(2)
      expect(tally[:named_count]).to eq(3)
    end

    it 'falls back to unknown when source_by_id has no match' do
      studies = [parsed_study(id: 'missing', event_id: nil, description: 'X-Ray')]
      tally = instance.send(:tally_parsed_studies, studies, {})

      expect(tally[:source_counts]).to eq('unknown' => 1)
    end

    it 'skips blank descriptions in unique name count' do
      studies = [
        parsed_study(id: 's1', description: 'CT Chest'),
        parsed_study(id: 's2', description: nil)
      ]

      tally = instance.send(:tally_parsed_studies, studies, { 's1' => 'vista', 's2' => 'vista' })

      expect(tally[:unique_name_count]).to eq(1)
      expect(tally[:named_count]).to eq(1)
    end
  end
end
