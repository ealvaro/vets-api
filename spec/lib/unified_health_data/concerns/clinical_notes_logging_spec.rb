# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/concerns/clinical_notes_logging'
require 'unified_health_data/source_constants'
require 'unified_health_data/models/clinical_notes'
require 'medical_records/medical_records_log'

RSpec.describe UnifiedHealthData::Concerns::ClinicalNotesLogging do
  subject(:instance) { test_class.new(user) }

  let(:user) { build(:user, :loa3) }

  # Create a lightweight test class that includes the concern
  let(:test_class) do
    klass = Class.new do
      include UnifiedHealthData::Concerns::ClinicalNotesLogging

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

  describe '#clinical_notes_logging_enabled?' do
    it 'returns true when the domain toggle is enabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)

      expect(instance.send(:clinical_notes_logging_enabled?)).to be true
    end

    it 'returns true when the global toggle is enabled as fallback' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(true)

      expect(instance.send(:clinical_notes_logging_enabled?)).to be true
    end

    it 'returns false when both toggles are disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      expect(instance.send(:clinical_notes_logging_enabled?)).to be false
    end
  end

  describe '#log_loinc_code_distribution' do
    let(:record1) { double('Record', loinc_codes: %w[11506-3 11506-3 18842-5]) }
    let(:record2) { double('Record', loinc_codes: %w[18842-5 28570-0]) }
    let(:records) { [record1, record2] }

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)
    end

    it 'logs LOINC code distribution via MedicalRecordsLog' do
      instance.send(:log_loinc_code_distribution, records, 'Clinical Notes')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'clinical_notes',
          action: 'loinc_distribution',
          record_type: 'Clinical Notes',
          loinc_code_distribution: '11506-3:2,18842-5:2,28570-0:1',
          total_codes: 3,
          total_records: 2,
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'defaults record_type to Clinical Notes' do
      instance.send(:log_loinc_code_distribution, records)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(record_type: 'Clinical Notes')
      )
    end

    it 'does not log when all LOINC codes are blank' do
      empty_records = [double('Record', loinc_codes: ['', nil])]

      instance.send(:log_loinc_code_distribution, empty_records)

      expect(Rails.logger).not_to have_received(:info)
    end

    it 'does not log when logging is disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      instance.send(:log_loinc_code_distribution, records)

      expect(Rails.logger).not_to have_received(:info)
    end
  end

  describe '#log_notes_response_count' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)
    end

    it 'logs the total, returned, and filtered counts via MedicalRecordsLog' do
      instance.send(:log_notes_response_count, 10, 7)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'clinical_notes',
          action: 'filter',
          total_doc_refs: 10,
          returned: 7,
          filtered: 3,
          log_level_context: 'diagnostic'
        )
      )
    end
  end

  describe '#log_notes_index_metrics' do
    let(:vista_note) { double('ClinicalNotes', source: 'vista') }
    let(:oh_note) { double('ClinicalNotes', source: 'oracle-health') }
    let(:parsed_notes) { [vista_note, vista_note, oh_note] }

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)
    end

    it 'logs the source breakdown via MedicalRecordsLog' do
      instance.send(:log_notes_index_metrics, parsed_notes, '2024-01-01', '2025-06-01')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'clinical_notes',
          action: 'index',
          total_notes: 3,
          vista_count: 2,
          oracle_health_count: 1,
          start_date: '2024-01-01',
          end_date: '2025-06-01',
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'emits StatsD gauges for each source' do
      instance.send(:log_notes_index_metrics, parsed_notes, '2024-01-01', '2025-06-01')

      expect(StatsD).to have_received(:gauge).with('api.uhd.clinical_notes.index.total', 3)
      expect(StatsD).to have_received(:gauge).with('api.uhd.clinical_notes.index.vista', 2)
      expect(StatsD).to have_received(:gauge).with('api.uhd.clinical_notes.index.oracle_health', 1)
    end
  end

  describe '#log_notes_show_metrics' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)
    end

    context 'when note is found' do
      let(:result) { double('ClinicalNotes', note_type: 'progress_note', present?: true) }

      it 'logs with the provided source and note_found true' do
        instance.send(:log_notes_show_metrics, 'oracle-health', result)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'show',
            source: 'oracle-health',
            note_found: true,
            note_type: 'progress_note',
            log_level_context: 'diagnostic'
          )
        )
      end

      it 'emits StatsD increment with the source tag' do
        instance.send(:log_notes_show_metrics, 'oracle-health', result)

        expect(StatsD).to have_received(:increment)
          .with('api.uhd.clinical_notes.show.source', tags: ['source:oracle-health'])
      end

      it 'does not emit a not_found warning or increment' do
        instance.send(:log_notes_show_metrics, 'oracle-health', result)

        expect(Rails.logger).not_to have_received(:warn)
        expect(StatsD).not_to have_received(:increment)
          .with('api.uhd.clinical_notes.show.not_found')
      end
    end

    context 'when note is not found' do
      it 'logs with note_found false and nil note_type' do
        instance.send(:log_notes_show_metrics, 'vista', nil)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            resource: 'clinical_notes',
            action: 'show',
            note_found: false,
            note_type: nil
          )
        )
      end

      it 'emits a warning with anomaly note_not_found' do
        instance.send(:log_notes_show_metrics, 'vista', nil)

        expect(Rails.logger).to have_received(:warn).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'show',
            anomaly: 'note_not_found',
            source: 'vista'
          )
        )
      end

      it 'emits a not_found StatsD increment' do
        instance.send(:log_notes_show_metrics, 'vista', nil)

        expect(StatsD).to have_received(:increment)
          .with('api.uhd.clinical_notes.show.not_found')
      end
    end

    context 'when source is nil (source not specified)' do
      let(:result) { double('ClinicalNotes', note_type: 'discharge_summary', present?: true) }

      it 'defaults source to source not specified' do
        instance.send(:log_notes_show_metrics, nil, result)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(source: 'source not specified')
        )
        expect(StatsD).to have_received(:increment)
          .with('api.uhd.clinical_notes.show.source', tags: ['source:source not specified'])
      end
    end
  end

  describe '#log_raw_source_counts' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)
    end

    it 'logs raw entry counts per source from the SCDF body' do
      body = {
        'vista' => { 'entry' => Array.new(5) },
        'oracle-health' => { 'entry' => Array.new(3) }
      }

      instance.send(:log_raw_source_counts, body)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'clinical_notes',
          action: 'index',
          stage: 'raw_from_scdf',
          vista_entry_count: 5,
          oracle_health_entry_count: 3,
          total_entry_count: 8,
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'handles missing source entries as zero' do
      body = { 'vista' => {} }

      instance.send(:log_raw_source_counts, body)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          vista_entry_count: 0,
          oracle_health_entry_count: 0,
          total_entry_count: 0
        )
      )
    end

    it 'does not log when diagnostic toggle is disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      instance.send(:log_raw_source_counts, { 'vista' => { 'entry' => [1] } })

      expect(Rails.logger).not_to have_received(:info)
    end
  end

  describe '#warn_high_filter_rate' do
    it 'warns when more than 50% of notes are filtered' do
      instance.send(:warn_high_filter_rate, 10, 4)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          service: 'medical_records',
          resource: 'clinical_notes',
          action: 'index',
          anomaly: 'high_filter_rate',
          filter_rate: 60.0,
          doc_ref_count: 10,
          returned_count: 4
        )
      )
    end

    it 'includes source_breakdown fields when provided' do
      breakdown = { vista_doc_refs: 6, oh_doc_refs: 4, vista_returned: 2, oh_returned: 2 }
      instance.send(:warn_high_filter_rate, 10, 4, source_breakdown: breakdown)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          anomaly: 'high_filter_rate',
          vista_doc_refs: 6,
          oh_doc_refs: 4,
          vista_returned: 2,
          oh_returned: 2
        )
      )
    end

    it 'emits a StatsD increment for the anomaly' do
      instance.send(:warn_high_filter_rate, 10, 4)

      expect(StatsD).to have_received(:increment)
        .with('api.uhd.clinical_notes.anomaly.high_filter_rate')
    end

    it 'does not warn when filter rate is at or below 50%' do
      instance.send(:warn_high_filter_rate, 10, 5)

      expect(Rails.logger).not_to have_received(:warn)
      expect(StatsD).not_to have_received(:increment)
        .with('api.uhd.clinical_notes.anomaly.high_filter_rate')
    end

    it 'does not warn when doc_ref_count is zero' do
      instance.send(:warn_high_filter_rate, 0, 0)

      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  describe '#warn_date_parse_failures' do
    it 'warns when failure count meets the threshold' do
      instance.send(:warn_date_parse_failures, 3, 20)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          service: 'medical_records',
          resource: 'clinical_notes',
          action: 'filter',
          anomaly: 'elevated_date_parse_failures',
          failure_count: 3,
          total_count: 20
        )
      )
    end

    it 'includes source_breakdown fields when provided' do
      breakdown = { 'vista' => 2, 'oracle-health' => 1 }
      instance.send(:warn_date_parse_failures, 3, 20, source_breakdown: breakdown)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          anomaly: 'elevated_date_parse_failures',
          'vista' => 2,
          'oracle-health' => 1
        )
      )
    end

    it 'emits a StatsD increment for the anomaly' do
      instance.send(:warn_date_parse_failures, 3, 20)

      expect(StatsD).to have_received(:increment)
        .with('api.uhd.clinical_notes.anomaly.date_parse_failures')
    end

    it 'does not warn when failure count is below the threshold' do
      instance.send(:warn_date_parse_failures, 2, 20)

      expect(Rails.logger).not_to have_received(:warn)
      expect(StatsD).not_to have_received(:increment)
        .with('api.uhd.clinical_notes.anomaly.date_parse_failures')
    end
  end

  describe '#log_care_summaries_metrics' do
    let(:vista_note) { double('ClinicalNotes', source: 'vista') }
    let(:oh_note) { double('ClinicalNotes', source: 'oracle-health') }
    let(:parsed_notes) { [vista_note, vista_note, oh_note] }

    let(:doc_ref_records) do
      [
        { 'source' => 'vista' },
        { 'source' => 'vista' },
        { 'source' => 'vista' },
        { 'source' => 'oracle-health' },
        { 'source' => 'oracle-health' }
      ]
    end

    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)
    end

    it 'logs response count and index metrics when logging is enabled' do
      instance.send(:log_care_summaries_metrics, doc_ref_records, parsed_notes, '2024-01-01', '2025-06-01')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          action: 'filter',
          total_doc_refs: 5,
          returned: 3,
          filtered: 2
        )
      )

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          action: 'index',
          total_notes: 3,
          vista_count: 2,
          oracle_health_count: 1
        )
      )
    end

    it 'triggers high filter rate warning when rate exceeds threshold' do
      # 5 doc_refs, 2 returned = 60% filtered
      small_parsed = [vista_note, oh_note]
      instance.send(:log_care_summaries_metrics, doc_ref_records, small_parsed, '2024-01-01', '2025-06-01')

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          anomaly: 'high_filter_rate',
          filter_rate: 60.0,
          doc_ref_count: 5,
          returned_count: 2,
          vista_doc_refs: 3,
          oh_doc_refs: 2,
          vista_returned: 1,
          oh_returned: 1
        )
      )
    end

    it 'does not warn when filter rate is at or below 50%' do
      # 5 doc_refs, 3 returned = 40% filtered
      instance.send(:log_care_summaries_metrics, doc_ref_records, parsed_notes, '2024-01-01', '2025-06-01')

      expect(Rails.logger).not_to have_received(:warn)
    end

    context 'when logging is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_diagnostic_logging, user)
          .and_return(false)
      end

      it 'skips diagnostic logs but still emits high filter rate warning' do
        small_parsed = [vista_note]
        instance.send(:log_care_summaries_metrics, doc_ref_records, small_parsed, '2024-01-01', '2025-06-01')

        expect(Rails.logger).not_to have_received(:info)
        expect(Rails.logger).to have_received(:warn).with(
          hash_including(anomaly: 'high_filter_rate')
        )
      end
    end
  end

  describe '#log_note_excluded_by_date' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(true)
    end

    let(:note) do
      instance_double(
        UnifiedHealthData::ClinicalNotes,
        id: 'note-123',
        date: '2024-06-15T10:00:00Z',
        note_type: 'physician_procedure_note',
        source: 'vista'
      )
    end

    it 'logs with blank_date reason' do
      blank_note = instance_double(
        UnifiedHealthData::ClinicalNotes,
        id: 'blank-note', date: nil, note_type: 'consult_result', source: 'oracle-health'
      )

      instance.send(:log_note_excluded_by_date, blank_note, reason: 'blank_date')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          resource: 'clinical_notes',
          action: 'filter',
          stage: 'date_range_exclusion',
          reason: 'blank_date',
          record_id: 'blank-note',
          note_date: nil,
          note_type: 'consult_result',
          source: 'oracle-health',
          log_level_context: 'diagnostic'
        )
      )
    end

    it 'logs with out_of_range reason' do
      instance.send(:log_note_excluded_by_date, note, reason: 'out_of_range')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          reason: 'out_of_range',
          record_id: 'note-123',
          note_date: '2024-06-15T10:00:00Z',
          source: 'vista'
        )
      )
    end

    it 'logs with unparseable_date reason' do
      instance.send(:log_note_excluded_by_date, note, reason: 'unparseable_date')

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          reason: 'unparseable_date',
          record_id: 'note-123'
        )
      )
    end

    it 'emits StatsD increment with reason and source tags' do
      instance.send(:log_note_excluded_by_date, note, reason: 'out_of_range')

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.clinical_notes.filter.date_range_exclusion',
        tags: ['reason:out_of_range', 'source:vista']
      )
    end

    it 'uses unknown source when note source is nil' do
      nil_source_note = instance_double(
        UnifiedHealthData::ClinicalNotes,
        id: 'x', date: nil, note_type: nil, source: nil
      )

      instance.send(:log_note_excluded_by_date, nil_source_note, reason: 'blank_date')

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.clinical_notes.filter.date_range_exclusion',
        tags: ['reason:blank_date', 'source:unknown']
      )
    end

    it 'does not log when diagnostic toggle is disabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_clinical_notes_diagnostic, user)
        .and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_diagnostic_logging, user)
        .and_return(false)

      instance.send(:log_note_excluded_by_date, note, reason: 'out_of_range')

      expect(Rails.logger).not_to have_received(:info)
      expect(StatsD).not_to have_received(:increment)
    end
  end
end
