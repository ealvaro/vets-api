# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/clinical_notes_adapter'

RSpec.describe 'ClinicalNotesAdapter' do
  let(:user) { build(:user, :loa3) }
  let(:adapter) { UnifiedHealthData::Adapters::ClinicalNotesAdapter.new(user:) }

  let(:notes_sample_response) do
    JSON.parse(Rails.root.join(
      'spec', 'fixtures', 'unified_health_data', 'notes_sample_response.json'
    ).read)
  end

  let(:notes_methods_fallback_response) do
    JSON.parse(Rails.root.join(
      'spec', 'fixtures', 'unified_health_data', 'notes_methods_fallback_response.json'
    ).read)
  end

  let(:avs_sample_response) do
    JSON.parse(Rails.root.join(
      'spec', 'fixtures', 'unified_health_data', 'after_visit_summary.json'
    ).read)
  end

  # Helper to find a fixture entry by resource ID, independent of array position.
  def find_vista_entry(id)
    notes_sample_response['vista']['entry'].find { |e| e['resource']['id'] == id }
  end

  def find_oh_entry(id)
    notes_sample_response['oracle-health']['entry'].find { |e| e['resource']['id'] == id }
  end

  # Well-known fixture IDs
  vista_standard_note_id = '76ad925b-0c2c-4401-ac0a-13542d6b6ef5'
  vista_single_addendum_note_id = '2e1d581e-bb36-4041-9350-40dbb5651d5c'
  vista_multi_addendum_note_id = '9b7034fd-ee22-41ff-8b10-1a18232f4711'
  oh_note_id = '15249697279'

  before do
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_medical_records_clinical_notes_diagnostic, user)
      .and_return(true)
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_medical_records_diagnostic_logging, user)
      .and_return(false)
  end

  describe '#parse' do
    it 'returns the expected fields for happy path for vista note with all fields' do
      note = find_vista_entry(vista_standard_note_id).merge('source' => 'vista')
      parsed_note = adapter.parse(note)

      expect(parsed_note).to have_attributes(
        {
          'id' => '76ad925b-0c2c-4401-ac0a-13542d6b6ef5',
          'name' => 'CARE COORDINATION HOME TELEHEALTH DISCHARGE NOTE',
          'note_type' => 'physician_procedure_note',
          'loinc_codes' => ['11506-3'],
          'date' => '2025-01-14T09:18:00.000+00:00',
          'date_signed' => '2025-01-14T09:29:26+00:00',
          'written_by' => 'MARCI P MCGUIRE',
          'signed_by' => 'MARCI P MCGUIRE',
          'discharge_date' => nil, # vista records do not have the context.period.end field
          'location' => 'CHYSHR TEST LAB',
          'note' => /VGhpcyBpcyBhIHRlc3QgdGVsZWhlYWx0aCBka/i,
          'source' => 'vista'
        }
      )
    end

    it 'returns the expected fields for happy path for OH note with all fields' do
      note = find_oh_entry(oh_note_id).merge('source' => 'oracle-health')
      parsed_note = adapter.parse(note)

      expect(parsed_note).to have_attributes(
        {
          'id' => '15249697279',
          'name' => 'Clinical Summary',
          'note_type' => 'discharge_summary',
          'loinc_codes' => %w[4189665 18842-5],
          'date' => '2025-07-29T17:48:41Z', # encounter-derived from context.period.end
          'date_signed' => nil, # OH records do not have a date signed field
          'written_by' => 'Victoria A Borland',
          'signed_by' => 'Victoria A Borland',
          'admission_date' => nil,
          'discharge_date' => '2025-07-29T17:48:41Z',
          'location' => '668 Mann-Grandstaff WA VA Medical Center',
          'note' => /Q2xpbmljYWwgU3VtbWFyeSAqIEZpbmFsIFJlcG9/i,
          'source' => 'oracle-health'
        }
      )
    end

    it 'returns the expected fields with alternate fallbacks for all fields' do
      parsed_note = adapter.parse(
        notes_methods_fallback_response['oracle-health']['entry'][0].merge('source' => 'oracle-health')
      )

      expect(parsed_note).to have_attributes(
        {
          'id' => '15249697279',
          'name' => 'Inpatient Clinical Summary', # type['text'] fallback
          'note_type' => 'discharge_summary', # based on LOINC code
          'loinc_codes' => %w[4189665 18842-5],
          'date' => '2025-07-29T17:48:41Z', # encounter-derived from context.period.end
          'date_signed' => nil,
          # name['text'] fallback (OH has a space after the , in name['text'], vista does not))
          'written_by' => ' Victoria A Borland',
          # name['text'] fallback (OH has a space after the , in name['text'], vista does not))
          'signed_by' => ' Victoria A Borland',
          # So far this doesn't exist in any sample data
          'admission_date' => nil,
          'discharge_date' => '2025-07-29T17:48:41Z',
          'location' => '668 Mann-Grandstaff WA VA Medical Center',
          'note' => /Q2xpbmljYWwgU3VtbWFyeSAqIEZpbmFsIFJlcG9/i
        }
      )
    end

    it 'returns nil for addenda on a standard (non-addendum) note' do
      note = find_vista_entry(vista_standard_note_id).merge('source' => 'vista')
      parsed_note = adapter.parse(note)

      expect(parsed_note.addenda).to be_nil
    end

    context 'single addendum note' do
      it 'parses original note content and a single addendum entry' do
        note = find_vista_entry(vista_single_addendum_note_id).merge('source' => 'vista')
        parsed_note = adapter.parse(note)

        # The outer record is the addendum; the contained doc is the original note.
        # Original note date should be the oldest (contained doc's date).
        expect(parsed_note.id).to eq(vista_single_addendum_note_id)
        expect(parsed_note.date).to eq('2024-12-17T17:13:00.000+00:00')
        expect(parsed_note.source).to eq('vista')

        # Original note content comes from the contained DocumentReference (oldest)
        expect(parsed_note.note).to match(/TGFyZ2UgbnVtYmVycyBvZiBiYWN0ZXJpYSBpbiB1/i)

        # One addendum entry from the outer record (newest)
        expect(parsed_note.addenda).to be_an(Array)
        expect(parsed_note.addenda.size).to eq(1)
        expect(parsed_note.addenda.first[:date]).to eq('2024-12-18T05:22:40.000+00:00')
        expect(parsed_note.addenda.first[:note]).to match(/VXJpbmFseXNpcyBwb3NpdGl2ZSBmb3IgUHJvdGV1/i)
      end
    end

    context 'multiple addendum note' do
      let(:note) { find_vista_entry(vista_multi_addendum_note_id).merge('source' => 'vista') }
      let(:parsed_note) { adapter.parse(note) }

      it 'parses original note content and multiple addenda entries in chronological order' do
        # The outer record (9b7034fd) is the newest addendum (THIRD addendum).
        # 3 contained DocumentReferences are referenced by relatesTo[code=appends]:
        #   6f64a6f8 (2026-03-25T14:55:18) - original note
        #   10e790a0 (2026-03-26T12:21:00) - FIRST addendum
        #   0fd5924f (2026-03-26T12:25:00) - SECOND addendum
        expect(parsed_note.id).to eq(vista_multi_addendum_note_id)
        expect(parsed_note.note_type).to eq('physician_procedure_note')
        expect(parsed_note.loinc_codes).to eq(['11506-3'])
        expect(parsed_note.source).to eq('vista')

        # Date should be from the original (oldest) contained note
        expect(parsed_note.date).to eq('2026-03-25T14:55:18+00:00')

        # Original note content from the oldest contained doc
        expect(parsed_note.note).to match(/RG9jdW1lbnRlZDogQ0hPTEVSQSwgTElWRSBBVFRF/i)

        expect(parsed_note.addenda).to be_an(Array)
        expect(parsed_note.addenda.size).to eq(3)

        # Addenda dates should all be more recent than the original note date
        # and should be in chronological order (oldest first)
        original_date = Time.zone.parse(parsed_note.date)
        addenda_dates = parsed_note.addenda.map { |a| Time.zone.parse(a[:date]) }

        expect(addenda_dates).to all(be > original_date)

        expect(addenda_dates).to eq(addenda_dates.sort)
      end

      it 'uses the original note title and author for the top-level fields' do
        # Name should come from the original (oldest) note or the outer record
        expect(parsed_note.name).to be_a(String)
        expect(parsed_note.name).not_to be_empty

        # Written-by/signed-by should come from the original note or fall back to outer
        expect(parsed_note.written_by).to be_a(String).or(be_nil)
        expect(parsed_note.signed_by).to be_a(String).or(be_nil)
      end

      it 'parses all fields for the first addendum (contained doc 10e790a0)' do
        first = parsed_note.addenda[0]
        expect(first).to include(
          date: '2026-03-26T12:21:00+00:00',
          date_signed: '2026-03-26T12:23:13+00:00',
          written_by: 'MARCI P MCGUIRE',
          signed_by: 'MARCI P MCGUIRE'
        )
        expect(first[:note]).to match(/SGVsbG8gaGVsbG8uICBUaGlzIGlzIHRoZSBGSVJT/i)
      end

      it 'parses all fields for the second addendum (contained doc 0fd5924f)' do
        second = parsed_note.addenda[1]
        expect(second).to include(
          date: '2026-03-26T12:25:00+00:00',
          date_signed: '2026-03-26T12:27:38+00:00',
          written_by: 'MARCI P MCGUIRE',
          signed_by: 'MARCI P MCGUIRE'
        )
        expect(second[:note]).to match(/SGkhIFRoaXMgaXMgdGhlIFNFQ09ORCBhZGRlbmR1/i)
      end

      it 'parses all fields for the third addendum (outer record 9b7034fd)' do
        third = parsed_note.addenda[2]
        expect(third).to include(
          date: '2026-03-26T12:29:00+00:00',
          date_signed: '2026-03-26T12:31:50+00:00',
          written_by: 'MARCI P MCGUIRE',
          signed_by: 'MARCI P MCGUIRE'
        )
        expect(third[:note]).to match(/SGksIHRoaXMgaXMgdGhlIFRISVJEIGFkZGVuZHVt/i)
      end
    end

    it 'private methods fail gracefully and returns the expected fields with nil for missing values' do
      parsed_note = adapter.parse(notes_methods_fallback_response['vista']['entry'][0])

      expect(parsed_note).to have_attributes(
        {
          'id' => '76ad925b-0c2c-4401-ac0a-13542d6b6ef5',
          'name' => nil,
          'note_type' => 'other', # based on LOINC code
          'loinc_codes' => nil,
          'date' => nil,
          'date_signed' => nil,
          'written_by' => 'MARCI P MCGUIRE', # alternate #mhv-practitioner-name format
          'signed_by' => nil, # name['text'] fallback
          'admission_date' => nil,
          'discharge_date' => nil,
          'location' => nil,
          'note' => /VGhpcyBpcyBhIHRlc3QgdGVsZWhlYWx0aCBk/i
        }
      )
    end

    it 'returns a parsed note with nil note field when there is no note data' do
      parsed_note = adapter.parse(notes_methods_fallback_response['vista']['entry'][1])

      expect(parsed_note).not_to be_nil
      expect(parsed_note.note).to be_nil
    end

    it 'returns a parsed note with nil note field for oracle-health records without binary content' do
      note = find_oh_entry(oh_note_id).deep_dup.merge('source' => 'oracle-health')
      note['resource']['content'].each { |c| c['attachment'].delete('data') }
      parsed_note = adapter.parse(note)

      expect(parsed_note).not_to be_nil
      expect(parsed_note.note).to be_nil
      expect(parsed_note.source).to eq('oracle-health')
      expect(parsed_note.id).to eq('15249697279')
    end

    context 'docStatus filtering' do
      it 'returns a parsed note when docStatus is final' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['docStatus'] = 'final'
        parsed_note = adapter.parse(note)

        expect(parsed_note).not_to be_nil
        expect(parsed_note.id).to eq('76ad925b-0c2c-4401-ac0a-13542d6b6ef5')
      end

      it 'returns a parsed note when docStatus is amended' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['docStatus'] = 'amended'
        parsed_note = adapter.parse(note)

        expect(parsed_note).not_to be_nil
        expect(parsed_note.id).to eq('76ad925b-0c2c-4401-ac0a-13542d6b6ef5')
      end

      it 'is case insensitive for docStatus' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['docStatus'] = 'Final'
        parsed_note = adapter.parse(note)

        expect(parsed_note).not_to be_nil
        expect(parsed_note.id).to eq('76ad925b-0c2c-4401-ac0a-13542d6b6ef5')
      end

      it 'returns nil when docStatus is preliminary' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['docStatus'] = 'preliminary'
        parsed_note = adapter.parse(note)

        expect(parsed_note).to be_nil
      end

      it 'returns nil when docStatus is entered-in-error' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['docStatus'] = 'entered-in-error'
        parsed_note = adapter.parse(note)

        expect(parsed_note).to be_nil
      end

      it 'returns nil when docStatus is nil' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource'].delete('docStatus')
        parsed_note = adapter.parse(note)

        expect(parsed_note).to be_nil
      end

      it 'logs filtered clinical notes with disallowed docStatus' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['docStatus'] = 'preliminary'

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'filter',
            record_id: '76ad925b-0c2c-4401-ac0a-13542d6b6ef5',
            doc_status: 'preliminary',
            reason: 'disallowed_doc_status',
            log_level_context: 'diagnostic'
          )
        )
        expect(StatsD).to receive(:increment).with(
          'unified_health_data.clinical_note.filtered_document_reference',
          tags: ['reason:disallowed_doc_status']
        )

        adapter.parse(note)
      end

      it 'logs filtered clinical notes with missing docStatus' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource'].delete('docStatus')

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'filter',
            record_id: '76ad925b-0c2c-4401-ac0a-13542d6b6ef5',
            reason: 'missing_doc_status',
            log_level_context: 'diagnostic'
          )
        )
        expect(StatsD).to receive(:increment).with(
          'unified_health_data.clinical_note.filtered_document_reference',
          tags: ['reason:missing_doc_status']
        )

        adapter.parse(note)
      end

      it 'does not log but still increments StatsD when toggle is disabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)

        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['docStatus'] = 'preliminary'

        expect(Rails.logger).not_to receive(:info)
        expect(StatsD).to receive(:increment).with(
          'unified_health_data.clinical_note.filtered_document_reference',
          tags: ['reason:disallowed_doc_status']
        )

        result = adapter.parse(note)
        expect(result).to be_nil
      end
    end

    context 'proactive warnings' do
      it 'warns when note content is empty' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        # Remove all content data to simulate empty note
        note['resource']['content'].each { |c| c['attachment'].delete('data') }

        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'parse',
            anomaly: 'empty_note_content',
            record_id: note['resource']['id']
          )
        )
        expect(StatsD).to receive(:increment).with('unified_health_data.clinical_note.empty_content')

        parsed = adapter.parse(note)
        expect(parsed).not_to be_nil
        expect(parsed.note).to be_nil
      end

      it 'does not warn when note content is present' do
        note = find_vista_entry(vista_standard_note_id).deep_dup

        expect(Rails.logger).not_to receive(:warn)
        expect(StatsD).not_to receive(:increment).with('unified_health_data.clinical_note.empty_content')

        parsed = adapter.parse(note)
        expect(parsed.note).not_to be_nil
      end

      it 'logs unknown LOINC code as diagnostic when toggle is enabled' do
        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['type']['coding'] = [{ 'code' => '99999-9', 'system' => 'http://loinc.org' }]

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'parse',
            anomaly: 'unknown_loinc_code',
            record_id: note['resource']['id'],
            loinc_codes: '99999-9'
          )
        )
        expect(StatsD).to receive(:increment).with('unified_health_data.clinical_note.unknown_loinc_code')

        parsed = adapter.parse(note)
        expect(parsed.note_type).to eq('other')
      end

      it 'does not log unknown LOINC code when toggle is disabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medical_records_clinical_notes_diagnostic, user)
          .and_return(false)

        note = find_vista_entry(vista_standard_note_id).deep_dup
        note['resource']['type']['coding'] = [{ 'code' => '99999-9', 'system' => 'http://loinc.org' }]

        expect(Rails.logger).not_to receive(:info).with(
          hash_including(anomaly: 'unknown_loinc_code')
        )
        expect(StatsD).to receive(:increment).with('unified_health_data.clinical_note.unknown_loinc_code')

        parsed = adapter.parse(note)
        expect(parsed.note_type).to eq('other')
      end

      it 'does not log when LOINC code is in known mapping' do
        note = find_vista_entry(vista_standard_note_id).deep_dup

        expect(Rails.logger).not_to receive(:info).with(
          hash_including(anomaly: 'unknown_loinc_code')
        )
        expect(StatsD).not_to receive(:increment).with('unified_health_data.clinical_note.unknown_loinc_code')

        adapter.parse(note)
      end
    end

    context 'OH encounter-based date derivation' do
      it 'uses context.period.end as date when present for OH standard note' do
        note = find_oh_entry(oh_note_id).deep_dup.merge('source' => 'oracle-health')
        parsed_note = adapter.parse(note)

        # context.period.end is '2025-07-29T17:48:41Z', DocumentReference.date is '2025-05-15T17:48:51Z'
        expect(parsed_note.date).to eq('2025-07-29T17:48:41Z')
      end

      it 'prefers context.period.start over context.period.end when both exist' do
        note = find_oh_entry(oh_note_id).deep_dup.merge('source' => 'oracle-health')
        note['resource']['context']['period']['start'] = '2025-07-28T10:00:00Z'

        parsed_note = adapter.parse(note)

        expect(parsed_note.date).to eq('2025-07-28T10:00:00Z')
      end

      it 'falls back to DocumentReference.date when context.period is absent and author is not TIU system' do
        note = find_oh_entry(oh_note_id).deep_dup.merge('source' => 'oracle-health')
        note['resource']['context'].delete('period')

        parsed_note = adapter.parse(note)

        expect(parsed_note.date).to eq('2025-05-15T17:48:51Z')
      end

      it 'does not fall back to DocumentReference.date when author is HX_VA_TIU_SYS' do
        note = find_oh_entry(oh_note_id).deep_dup.merge('source' => 'oracle-health')
        note['resource']['context'].delete('period')
        note['resource']['author'] = [
          { 'reference' => 'Practitioner/14883417', 'display' => 'Contributor_system, HX_VA_TIU_SYS' }
        ]

        parsed_note = adapter.parse(note)

        expect(parsed_note.date).to be_nil
      end

      it 'uses encounter date even when author is HX_VA_TIU_SYS if context.period is present' do
        note = find_oh_entry(oh_note_id).deep_dup.merge('source' => 'oracle-health')
        note['resource']['author'] = [
          { 'reference' => 'Practitioner/14883417', 'display' => 'Contributor_system, HX_VA_TIU_SYS' }
        ]

        parsed_note = adapter.parse(note)

        # context.period.end should still be used
        expect(parsed_note.date).to eq('2025-07-29T17:48:41Z')
      end

      it 'does not change VistA note date behavior' do
        note = find_vista_entry(vista_standard_note_id).merge('source' => 'vista')
        parsed_note = adapter.parse(note)

        # VistA notes should continue using DocumentReference.date
        expect(parsed_note.date).to eq('2025-01-14T09:18:00.000+00:00')
      end

      it 'sets sort_date from the encounter-derived date' do
        note = find_oh_entry(oh_note_id).deep_dup.merge('source' => 'oracle-health')
        parsed_note = adapter.parse(note)

        # sort_date should be normalized from the encounter-derived date, not DocRef.date
        expect(parsed_note.sort_date).to eq(adapter.send(:normalize_date_for_sorting, '2025-07-29T17:48:41Z'))
      end
    end
  end

  describe 'derive_oh_date fallback_record behavior' do
    # Test the private method directly to cover addendum scenarios where the contained doc
    # (original_doc) may lack context.period but the outer record has it.

    it 'uses fallback_record context.period.end when record has no context.period' do
      record = { 'date' => '2026-01-01T00:00:00Z' }
      fallback = { 'context' => { 'period' => { 'end' => '2026-02-15T10:00:00Z' } } }

      result = adapter.send(:derive_oh_date, record, fallback_record: fallback)
      expect(result).to eq('2026-02-15T10:00:00Z')
    end

    it 'uses fallback_record context.period.start when record has no context.period' do
      record = { 'date' => '2026-01-01T00:00:00Z' }
      fallback = {
        'context' => { 'period' => { 'start' => '2026-02-14T08:00:00Z', 'end' => '2026-02-15T10:00:00Z' } }
      }

      result = adapter.send(:derive_oh_date, record, fallback_record: fallback)
      expect(result).to eq('2026-02-14T08:00:00Z')
    end

    it 'prefers record context.period.start over fallback context.period.start' do
      record = { 'context' => { 'period' => { 'start' => '2026-03-01T09:00:00Z' } } }
      fallback = { 'context' => { 'period' => { 'start' => '2026-02-14T08:00:00Z' } } }

      result = adapter.send(:derive_oh_date, record, fallback_record: fallback)
      expect(result).to eq('2026-03-01T09:00:00Z')
    end

    it 'prefers fallback start over record end (start always beats end)' do
      record = { 'context' => { 'period' => { 'end' => '2026-03-02T17:00:00Z' } },
                 'date' => '2026-01-01T00:00:00Z' }
      fallback = { 'context' => { 'period' => { 'start' => '2026-02-28T08:00:00Z' } } }

      result = adapter.send(:derive_oh_date, record, fallback_record: fallback)
      expect(result).to eq('2026-02-28T08:00:00Z')
    end

    it 'falls back to record date when neither record nor fallback has context.period' do
      record = { 'date' => '2026-01-01T00:00:00Z', 'author' => [] }
      fallback = { 'context' => {} }

      result = adapter.send(:derive_oh_date, record, fallback_record: fallback)
      expect(result).to eq('2026-01-01T00:00:00Z')
    end

    it 'returns nil when no context.period and author is TIU system' do
      record = { 'date' => '2026-01-01T00:00:00Z',
                 'author' => [{ 'display' => 'Contributor_system, HX_VA_TIU_SYS' }] }
      fallback = {}

      result = adapter.send(:derive_oh_date, record, fallback_record: fallback)
      expect(result).to be_nil
    end
  end

  describe 'error handling in addenda entry methods' do
    context 'build_addendum_entry' do
      it 'logs a warning and returns nil when a rescued error occurs inside build_addendum_entry' do
        # A doc missing the 'authenticator' key entirely but with content that passes the blank
        # check. extract_authenticator is stubbed to raise NoMethodError, simulating a scenario
        # where the error propagates up to build_addendum_entry's rescue.
        malformed_doc = {
          'id' => 'malformed-addendum-001',
          'date' => '2025-01-01T00:00:00Z',
          'content' => [{ 'attachment' => { 'contentType' => 'text/plain', 'data' => 'c29tZSB0ZXh0' } }]
        }
        allow(adapter).to receive(:extract_authenticator).with(malformed_doc, contained: nil)
                                                         .and_raise(NoMethodError, 'undefined method `[]` for nil')

        # get_date_signed now catches its own NoMethodError on the malformed doc and logs a
        # warning before extract_authenticator is called. Allow that inner warning through.
        allow(Rails.logger).to receive(:warn).with(
          hash_including(
            action: 'get_date_signed',
            anomaly: 'get_date_signed_failed'
          )
        )

        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'build_addendum_entry',
            anomaly: 'note_entry_skipped',
            record_id: 'malformed-addendum-001',
            error_class: 'NoMethodError'
          )
        )
        expect(StatsD).to receive(:increment).with('unified_health_data.clinical_note.note_entry_skipped')

        result = adapter.send(:build_addendum_entry, malformed_doc)
        expect(result).to be_nil
      end

      it 'returns nil without logging when content is blank' do
        # A well-formed doc with no extractable content should return nil (not an error)
        empty_doc = { 'content' => [] }

        expect(Rails.logger).not_to receive(:warn)
        expect(StatsD).not_to receive(:increment).with('unified_health_data.clinical_note.note_entry_skipped')

        result = adapter.send(:build_addendum_entry, empty_doc)
        expect(result).to be_nil
      end

      it 'returns empty addenda when build_addendum_entry returns nil for all entries' do
        note = find_vista_entry(vista_single_addendum_note_id).deep_dup.merge('source' => 'vista')
        # Stub build_addendum_entry to return nil (simulating blank content / rescued error)
        allow(adapter).to receive(:build_addendum_entry).and_return(nil)

        parsed_note = adapter.parse(note)
        expect(parsed_note).not_to be_nil
        expect(parsed_note.addenda).to eq([])
      end
    end

    context 'get_all_appended_documents' do
      it 'logs a warning and returns empty array when extraction fails due to malformed relatesTo' do
        note = find_vista_entry(vista_single_addendum_note_id).deep_dup.merge('source' => 'vista')
        # Break the relatesTo target to cause a NoMethodError during dig
        note['resource']['relatesTo'] = [{ 'code' => 'appends', 'target' => 'not_a_hash' }]

        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            service: 'medical_records',
            resource: 'clinical_notes',
            action: 'get_all_appended_documents',
            anomaly: 'appended_documents_extraction_failed'
          )
        )

        # The note still parses — appended docs are empty, falls back to standard behavior
        parsed_note = adapter.parse(note)
        expect(parsed_note).not_to be_nil
      end
    end
  end

  describe '#parse_avs_with_metadata' do
    context 'happy path' do
      it 'returns the expected fields with binary data included' do
        parsed_avs = adapter.parse_avs_with_metadata(avs_sample_response['entry'][1], '12345', true)

        expect(parsed_avs).to have_attributes(
          {
            'appt_id' => '12345',
            'id' => '15249638961',
            'name' => 'Ambulatory Visit Summary',
            'loinc_codes' => %w[4189669 96345-4],
            'note_type' => 'ambulatory_patient_summary',
            'content_type' => 'application/pdf',
            'binary' => /JVBERi0xLjQKJeLjz9MKMSAwIG9iago8P/i
          }
        )
      end

      it 'returns the expected fields when include_binary is false' do
        parsed_avs = adapter.parse_avs_with_metadata(avs_sample_response['entry'][1], '12345', false)

        expect(parsed_avs).to have_attributes(
          {
            'appt_id' => '12345',
            'id' => '15249638961',
            'name' => 'Ambulatory Visit Summary',
            'loinc_codes' => %w[4189669 96345-4],
            'note_type' => 'ambulatory_patient_summary',
            'content_type' => 'application/pdf',
            'binary' => nil
          }
        )
      end
    end

    context 'edge cases and fallbacks' do
      it 'returns the expected fields for a text only with binary data included' do
        modified_sample = avs_sample_response['entry'][1].deep_dup
        modified_sample['resource']['contained'] = [] # remove the contained array to test content text fallback option
        parsed_avs = adapter.parse_avs_with_metadata(modified_sample, '12345', true)

        expect(parsed_avs).to have_attributes(
          {
            'appt_id' => '12345',
            'id' => '15249638961',
            'name' => 'Ambulatory Visit Summary',
            'loinc_codes' => %w[4189669 96345-4],
            'note_type' => 'ambulatory_patient_summary',
            'content_type' => 'text/plain',
            'binary' => /NjY4IE1hbm4tR3JhbmRzdGFmZiBXQSBWQSBNZWRpY2FsIENlbnRlcgo0OD/i
          }
        )
      end

      it 'returns the expected fields for text only in the contained array' do
        modified_sample = avs_sample_response['entry'][1].deep_dup
        modified_sample['resource']['contained'][0]['contentType'] = 'text/plain'
        parsed_avs = adapter.parse_avs_with_metadata(modified_sample, '12345', true)

        expect(parsed_avs).to have_attributes(
          {
            'appt_id' => '12345',
            'id' => '15249638961',
            'name' => 'Ambulatory Visit Summary',
            'loinc_codes' => %w[4189669 96345-4],
            'note_type' => 'ambulatory_patient_summary',
            'content_type' => 'text/plain',
            'binary' => /JVBERi0xLjQKJeLjz9MKMSAwIG9iago8P/i
          }
        )
      end

      it 'returns the expected fields if XML only in the contained array' do
        modified_sample = avs_sample_response['entry'][1].deep_dup
        modified_sample['resource']['contained'][0]['contentType'] = 'application/xml'
        parsed_avs = adapter.parse_avs_with_metadata(modified_sample, '12345', true)

        expect(parsed_avs).to have_attributes(
          {
            'appt_id' => '12345',
            'id' => '15249638961',
            'name' => 'Ambulatory Visit Summary',
            'loinc_codes' => %w[4189669 96345-4],
            'note_type' => 'ambulatory_patient_summary',
            'content_type' => 'text/plain', # should skip the contained XML and use the content text fallback
            'binary' => /NjY4IE1hbm4tR3JhbmRzdGFmZiBXQSBWQSBNZWRpY2FsIENlbnRlcgo0OD/i
          }
        )
      end

      it 'returns nil if there is no binary data returned even if include_binary is false' do
        modified_sample = avs_sample_response['entry'][1].deep_dup
        modified_sample['resource']['contained'] = [] # remove the contained array
        modified_sample['resource']['content'] = [] # remove the content array
        parsed_avs = adapter.parse_avs_with_metadata(modified_sample, '12345', false)

        expect(parsed_avs).to be_nil
      end

      it 'returns nil if the only binary option is XML' do
        modified_sample = avs_sample_response['entry'][1].deep_dup
        modified_sample['resource']['contained'] = [] # remove the contained array
        modified_sample['resource']['content'] = [{
          'attachment' => {
            'contentType' => 'application/xml',
            'url' => 'http://fake.url.com/Binary/XML-15249651470',
            'title' => 'Ambulatory Visit Summary',
            'creation' => '2025-07-29T17:32:46.000Z'
          },
          'format' => {
            'system' => 'http://fake.system/ValueSet/IHE.FormatCode.codesystem',
            'code' => 'urn:mimeTypeSufficient',
            'display' => 'mimeType Sufficient'
          }
        }] # replace the content array with only an XML option
        parsed_avs = adapter.parse_avs_with_metadata(modified_sample, '12345', true)

        expect(parsed_avs).to be_nil
      end
    end
  end

  describe '#build_avs_metadata_by_appointment' do
    let(:doc_ref) do
      {
        'id' => 'doc-ref-1',
        'type' => {
          'coding' => [
            { 'system' => 'http://loinc.org', 'code' => '96345-4' }
          ]
        },
        'content' => [
          { 'attachment' => { 'contentType' => 'application/pdf' } },
          { 'attachment' => { 'contentType' => 'application/xml' } }
        ],
        'context' => {
          'encounter' => [{ 'reference' => 'Encounter/enc-1' }]
        }
      }
    end

    let(:encounter) do
      {
        'id' => 'enc-1',
        'appointment' => [{ 'reference' => 'Appointment/appt-123' }]
      }
    end

    it 'returns a hash of AfterVisitSummary objects indexed by appointment id' do
      result = adapter.build_avs_metadata_by_appointment([encounter], [doc_ref])
      expect(result['appt-123']).to be_an(Array)
      avs = result['appt-123'].first
      expect(avs).to be_a(UnifiedHealthData::AfterVisitSummary)
      expect(avs.id).to eq('doc-ref-1')
      expect(avs.appt_id).to eq('appt-123')
      expect(avs.loinc_codes).to include('96345-4')
      expect(avs.content_type).to eq('application/pdf')
      expect(avs.binary).to be_nil
    end

    it 'filters out non-AVS content types (xml, html) from content_type' do
      doc_ref_xml_only = doc_ref.deep_dup
      doc_ref_xml_only['content'] = [
        { 'attachment' => { 'contentType' => 'application/xml' } },
        { 'attachment' => { 'contentType' => 'text/html' } }
      ]
      result = adapter.build_avs_metadata_by_appointment([encounter], [doc_ref_xml_only])
      avs = result['appt-123'].first
      expect(avs.content_type).to be_nil
    end

    it 'maps one encounter to multiple appointments' do
      enc = encounter.deep_dup
      enc['appointment'] << { 'reference' => 'Appointment/appt-456' }
      result = adapter.build_avs_metadata_by_appointment([enc], [doc_ref])
      expect(result.keys).to contain_exactly('appt-123', 'appt-456')
      expect(result['appt-456'].first.appt_id).to eq('appt-456')
    end

    it 'skips non-hash encounters' do
      result = adapter.build_avs_metadata_by_appointment(['not-a-hash', nil], [doc_ref])
      expect(result).to be_empty
    end

    it 'skips encounters with a blank id' do
      enc = encounter.merge('id' => '')
      result = adapter.build_avs_metadata_by_appointment([enc], [doc_ref])
      expect(result).to be_empty
    end

    it 'skips encounters with no appointment references' do
      enc = encounter.merge('appointment' => [])
      result = adapter.build_avs_metadata_by_appointment([enc], [doc_ref])
      expect(result).to be_empty
    end

    it 'returns empty hash when given empty arrays' do
      result = adapter.build_avs_metadata_by_appointment([], [])
      expect(result).to be_empty
    end

    it 'sets note_type from AVS loinc code mapping' do
      result = adapter.build_avs_metadata_by_appointment([encounter], [doc_ref])
      avs = result['appt-123'].first
      expect(avs.note_type).to eq('ambulatory_patient_summary')
    end

    it 'unions loinc codes across multiple doc refs for the same encounter' do
      doc_ref2 = doc_ref.deep_dup
      doc_ref2['type']['coding'] = [{ 'code' => '68834-1' }]
      doc_ref2['content'] = [{ 'attachment' => { 'contentType' => 'text/plain' } }]
      result = adapter.build_avs_metadata_by_appointment([encounter], [doc_ref, doc_ref2])
      avs = result['appt-123'].first
      expect(avs.loinc_codes).to contain_exactly('96345-4', '68834-1')
    end

    it 'handles encounters with no matching doc refs' do
      result = adapter.build_avs_metadata_by_appointment([encounter], [])
      avs = result['appt-123'].first
      expect(avs.loinc_codes).to be_nil
      expect(avs.content_type).to be_nil
      expect(avs.note_type).to be_nil
    end
  end

  # ==========================================================================
  # Null/nil exception regression tests (fixes 3a–3f)
  # ==========================================================================
  describe 'null/nil exception guards' do
    # 3a. get_record_type — nil record['type']
    describe '#parse — nil record type (fix 3a)' do
      it 'does not crash when record type is nil' do
        note = {
          'resource' => {
            'id' => 'cn-3a',
            'docStatus' => 'final',
            'content' => [{ 'attachment' => { 'contentType' => 'text/plain', 'data' => 'dGVzdA==' } }]
          }
        }
        parsed = adapter.parse(note)
        expect(parsed).not_to be_nil
        expect(parsed.note_type).to eq('other')
      end
    end

    # 3b. get_avs_record_type — nil record['type']
    describe '#parse_avs_with_metadata — nil record type (fix 3b)' do
      it 'does not crash when AVS record type is nil' do
        avs = {
          'resource' => {
            'id' => 'cn-3b',
            'contained' => [{ 'resourceType' => 'Binary', 'contentType' => 'application/pdf', 'data' => 'JVBER' }],
            'content' => []
          }
        }
        parsed = adapter.parse_avs_with_metadata(avs, 'appt-1', false)
        expect(parsed).not_to be_nil
        expect(parsed.note_type).to eq('other')
      end
    end

    # 3c. get_loinc_codes — nil record['type']
    describe '#get_loinc_codes — nil record type (fix 3c)' do
      it 'returns nil when record has no type key' do
        result = adapter.send(:get_loinc_codes, {})
        expect(result).to be_nil
      end

      it 'returns nil when type has no coding' do
        result = adapter.send(:get_loinc_codes, { 'type' => {} })
        expect(result).to be_nil
      end
    end

    # 3d. get_title — find returns nil
    describe '#get_title — no content items have attachment (fix 3d)' do
      it 'returns nil when no content items have attachment' do
        record = { 'content' => [{ 'format' => 'text/plain' }] }
        result = adapter.send(:get_title, record)
        expect(result).to be_nil
      end

      it 'returns nil when content is nil' do
        record = {}
        result = adapter.send(:get_title, record)
        expect(result).to be_nil
      end

      it 'falls back to type.text when attachment has no title' do
        record = {
          'content' => [{ 'attachment' => { 'contentType' => 'text/plain' } }],
          'type' => { 'text' => 'Discharge Summary' }
        }
        result = adapter.send(:get_title, record)
        expect(result).to eq('Discharge Summary')
      end
    end

    # 3e. extract_avs_binary — nil attachment in content items
    describe '#extract_avs_binary — content items with nil attachment (fix 3e)' do
      it 'does not crash when content item has no attachment key' do
        record = {
          'contained' => [],
          'content' => [
            { 'format' => 'text/plain' },
            { 'attachment' => { 'data' => 'dGVzdA==', 'contentType' => 'text/plain' } }
          ]
        }
        result = adapter.send(:extract_avs_binary, record)
        expect(result).not_to be_nil
        expect(result[:content_type]).to eq('text/plain')
      end

      it 'returns nil when no content items have valid attachment data' do
        record = {
          'contained' => [],
          'content' => [{ 'format' => 'text/plain' }]
        }
        result = adapter.send(:extract_avs_binary, record)
        expect(result).to be_nil
      end
    end

    # 3f. get_note — find returns nil
    describe '#get_note — no text/plain content item (fix 3f)' do
      it 'returns nil when no content item has text/plain contentType' do
        record = {
          'content' => [
            { 'attachment' => { 'contentType' => 'application/pdf', 'data' => 'JVBER' } }
          ]
        }
        result = adapter.send(:get_note, record)
        expect(result).to be_nil
      end

      it 'does not crash when content items have no attachment key' do
        record = {
          'content' => [{ 'format' => 'text/plain' }]
        }
        result = adapter.send(:get_note, record)
        expect(result).to be_nil
      end
    end
  end
end
