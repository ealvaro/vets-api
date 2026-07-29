# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/allergy_adapter'
require 'unified_health_data/models/allergy'

RSpec.describe 'AllergyAdapter' do
  let(:adapter) { UnifiedHealthData::Adapters::AllergyAdapter.new }
  let(:allergy_sample_response) do
    JSON.parse(Rails.root.join(
      'spec', 'fixtures', 'unified_health_data', 'allergies_example.json'
    ).read)
  end

  # Shared fixture for testing name filtering - an allergy with active status but no name
  let(:record_without_name) do
    {
      'resource' => {
        'resourceType' => 'AllergyIntolerance',
        'id' => 'no-name-allergy',
        'clinicalStatus' => {
          'coding' => [{ 'code' => 'active' }]
        },
        'code' => {
          'coding' => [{ 'system' => 'http://snomed.info/sct', 'code' => '12345' }]
          # No 'display' or 'text' field
        }
      }
    }
  end

  before do
    allow(UnifiedHealthData::Allergy).to receive(:new).and_call_original
  end

  describe '#parse' do
    # Helper method to simulate what the service's remap_vista_identifier does
    def add_vista_ids(vista_records)
      vista_records.each do |record|
        resource = record['resource']
        next unless resource && resource['identifier']

        identifier = resource['identifier'].find { |id| id['system']&.starts_with?('https://va.gov/systems/') }
        resource['id'] = identifier['value'] if identifier
      end
    end

    context 'when filter_by_status is true (default)' do
      it 'filters out VistA allergies without active clinicalStatus' do
        vista_records = allergy_sample_response['vista']['entry']
        # Add IDs like the service's remap_vista_identifier method does
        add_vista_ids(vista_records)

        # First verify that a non-active record exists in fixture data
        # ASPIRIN (id 2676) has no clinicalStatus, so it should be filtered out
        non_active_record = vista_records.find { |r| r['resource']['id'] == '2676' }
        expect(non_active_record).to be_present, 'Fixture must contain VistA allergy with id 2676'
        expect(non_active_record.dig('resource', 'clinicalStatus', 'coding', 0, 'code')).to be_nil

        # VistA fixture has 6 entries total, but only 5 are AllergyIntolerance resources
        # 1 of those has no clinicalStatus (not active)
        expect(vista_records.length).to eq(6)

        parsed_allergies = adapter.parse(vista_records)

        # Should filter out records without active clinicalStatus, leaving 4
        expect(parsed_allergies.length).to eq(4)
        allergy_ids = parsed_allergies.map(&:id)
        expect(allergy_ids).not_to include('2676')
      end

      it 'filters out Oracle Health allergies without active clinicalStatus' do
        oh_records = allergy_sample_response['oracle-health']['entry']

        # First verify that non-active records exist in fixture data
        # Grass (id 132312405) has 'resolved' status, Cashews (id 132316427) has no clinicalStatus
        resolved_record = oh_records.find { |r| r['resource']['id'] == '132312405' }
        expect(resolved_record).to be_present, 'Fixture must contain OH allergy with id 132312405'
        expect(resolved_record.dig('resource', 'clinicalStatus', 'coding', 0, 'code')).to eq('resolved')

        no_status_record = oh_records.find { |r| r['resource']['id'] == '132316427' }
        expect(no_status_record).to be_present, 'Fixture must contain OH allergy with id 132316427'
        expect(no_status_record.dig('resource', 'clinicalStatus', 'coding', 0, 'code')).to be_nil

        # OH fixture has 10 entries total, but only 8 are AllergyIntolerance resources
        # 2 of those don't have active clinicalStatus (1 resolved, 1 nil)
        expect(oh_records.length).to eq(10)

        parsed_allergies = adapter.parse(oh_records)

        # Should filter out records without active clinicalStatus, leaving 6
        expect(parsed_allergies.length).to eq(6)
        allergy_ids = parsed_allergies.map(&:id)
        expect(allergy_ids).not_to include('132312405')
        expect(allergy_ids).not_to include('132316427')
      end

      it 'includes allergies with active clinicalStatus' do
        vista_records = allergy_sample_response['vista']['entry']
        add_vista_ids(vista_records)
        parsed_allergies = adapter.parse(vista_records)

        # Should include active allergies like TRAZODONE
        allergy_names = parsed_allergies.map(&:name)
        expect(allergy_names).to include('TRAZODONE')
      end

      it 'includes Oracle Health allergies with active clinicalStatus' do
        oh_records = allergy_sample_response['oracle-health']['entry']
        parsed_allergies = adapter.parse(oh_records)

        # Should include active allergies like Penicillin
        allergy_names = parsed_allergies.map(&:name)
        expect(allergy_names).to include('Penicillin')
      end

      it 'filters out allergies without a name' do
        oh_records = allergy_sample_response['oracle-health']['entry'] + [record_without_name]
        parsed_allergies = adapter.parse(oh_records)

        # Should not include the allergy without a name
        allergy_ids = parsed_allergies.map(&:id)
        expect(allergy_ids).not_to include('no-name-allergy')
      end
    end

    context 'when filter_by_status is false' do
      it 'includes VistA allergies without active clinicalStatus' do
        vista_records = allergy_sample_response['vista']['entry']
        # Add IDs like the service's remap_vista_identifier method does
        add_vista_ids(vista_records)

        parsed_allergies = adapter.parse(vista_records, filter_by_status: false)

        # Should include all 5 AllergyIntolerance records, including ASPIRIN with no clinicalStatus
        expect(parsed_allergies.length).to eq(5)
        allergy_ids = parsed_allergies.map(&:id)
        expect(allergy_ids).to include('2676')
        allergy_names = parsed_allergies.map(&:name)
        expect(allergy_names).to include('ASPIRIN')
      end

      it 'includes Oracle Health allergies without active clinicalStatus' do
        oh_records = allergy_sample_response['oracle-health']['entry']
        parsed_allergies = adapter.parse(oh_records, filter_by_status: false)

        # Should include all 8 AllergyIntolerance records
        expect(parsed_allergies.length).to eq(8)
        allergy_ids = parsed_allergies.map(&:id)
        # Includes resolved allergy (Grass)
        expect(allergy_ids).to include('132312405')
        # Includes allergy with no clinicalStatus (Cashews)
        expect(allergy_ids).to include('132316427')
      end

      it 'still filters out allergies without a name even when filter_by_status is false' do
        oh_records = allergy_sample_response['oracle-health']['entry'] + [record_without_name]
        parsed_allergies = adapter.parse(oh_records, filter_by_status: false)

        # Should not include the allergy without a name, even with filter_by_status: false
        allergy_ids = parsed_allergies.map(&:id)
        expect(allergy_ids).not_to include('no-name-allergy')
      end
    end
  end

  describe '#parse_single_allergy' do
    # Helper to find a VistA record without active clinicalStatus (ASPIRIN with id 2676)
    def vista_non_active_record
      allergy_sample_response['vista']['entry'].find do |record|
        identifiers = record.dig('resource', 'identifier') || []
        identifiers.any? { |id| id['value'] == '2676' }
      end
    end

    # Helper to find an Oracle Health record with resolved clinicalStatus (Grass with id 132312405)
    def oh_resolved_record
      allergy_sample_response['oracle-health']['entry'].find do |record|
        record.dig('resource', 'id') == '132312405'
      end
    end

    context 'when filter_by_status is true (default)' do
      it 'returns nil for VistA allergy without active clinicalStatus' do
        record = vista_non_active_record
        parsed_allergy = adapter.parse_single_allergy(record)

        expect(parsed_allergy).to be_nil
      end

      it 'returns nil for Oracle Health allergy with resolved clinicalStatus' do
        record = oh_resolved_record
        parsed_allergy = adapter.parse_single_allergy(record)

        expect(parsed_allergy).to be_nil
      end

      it 'returns the allergy for VistA record with active clinicalStatus' do
        vista_single_record = allergy_sample_response['vista']['entry'][0]
        vista_identifier = vista_single_record['resource']['identifier'].find { |id| id['system'].starts_with?('https://va.gov/systems/') }
        vista_single_record['resource']['id'] = vista_identifier['value']

        parsed_allergy = adapter.parse_single_allergy(vista_single_record)

        expect(parsed_allergy).not_to be_nil
        expect(parsed_allergy.name).to eq('TRAZODONE')
      end

      it 'returns the allergy for Oracle Health record with active clinicalStatus' do
        parsed_allergy = adapter.parse_single_allergy(allergy_sample_response['oracle-health']['entry'][0])

        expect(parsed_allergy).not_to be_nil
        expect(parsed_allergy.name).to eq('Penicillin')
      end

      it 'returns nil for allergy without a name' do
        parsed_allergy = adapter.parse_single_allergy(record_without_name)
        expect(parsed_allergy).to be_nil
      end
    end

    context 'when filter_by_status is false' do
      it 'returns VistA allergy without active clinicalStatus' do
        record = vista_non_active_record
        # Add ID like the service does
        identifier = record['resource']['identifier'].find { |id| id['system']&.starts_with?('https://va.gov/systems/') }
        record['resource']['id'] = identifier['value'] if identifier

        parsed_allergy = adapter.parse_single_allergy(record, filter_by_status: false)

        expect(parsed_allergy).not_to be_nil
        expect(parsed_allergy.name).to eq('ASPIRIN')
        expect(parsed_allergy.id).to eq('2676')
      end

      it 'returns Oracle Health allergy with resolved clinicalStatus' do
        record = oh_resolved_record
        parsed_allergy = adapter.parse_single_allergy(record, filter_by_status: false)

        expect(parsed_allergy).not_to be_nil
        expect(parsed_allergy.name).to eq('Grass pollen (substance)')
        expect(parsed_allergy.id).to eq('132312405')
      end

      it 'still returns nil for allergy without a name even when filter_by_status is false' do
        parsed_allergy = adapter.parse_single_allergy(record_without_name, filter_by_status: false)
        expect(parsed_allergy).to be_nil
      end
    end

    it 'returns the expected fields for happy path for vista allergy with all fields' do
      vista_single_record = allergy_sample_response['vista']['entry'][0]
      # This normally happens in the service, but we need the id for the test so we're mocking it here
      vista_identifier = vista_single_record['resource']['identifier'].find { |id| id['system'].starts_with?('https://va.gov/systems/') }
      vista_single_record['resource']['id'] = vista_identifier['value']
      # This also checks fallbacks and nil guards since VistA data is missing many fields
      parsed_allergy = adapter.parse_single_allergy(vista_single_record)

      expect(parsed_allergy).to have_attributes(
        {
          'id' => '2678',
          'name' => 'TRAZODONE',
          'date' => nil,
          'categories' => ['medication'],
          'reactions' => [],
          'location' => nil, # Neither OH nor VistA samples have location names
          'observedHistoric' => 'h',
          'notes' => [],
          'provider' => nil
        }
      )
    end

    it 'returns the expected fields for happy path for OH allergy with all fields' do
      parsed_allergy = adapter.parse_single_allergy(allergy_sample_response['oracle-health']['entry'][0])

      expect(parsed_allergy).to have_attributes(
        {
          'id' => '132892323',
          'name' => 'Penicillin',
          'date' => '2025-02-25T17:50:49Z',
          'categories' => ['medication'],
          'reactions' => ['Urticaria (Hives)', 'Sneezing'],
          'location' => nil, # Neither OH nor VistA samples have location names
          'observedHistoric' => nil, # OH data does not have this field
          'notes' => ['Patient reports adverse reaction to previously prescribed pencicillins'],
          'provider' => ' Victoria A Borland'
        }
      )
    end

    it 'uses recordedDate when both recordedDate and onsetDateTime are present' do
      allow(StatsD).to receive(:increment)

      record = {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'allergy-with-both-dates',
          'clinicalStatus' => {
            'coding' => [{ 'code' => 'active' }]
          },
          'code' => {
            'text' => 'Pollen'
          },
          'recordedDate' => '2023-05-01T00:00:00+00:00',
          'onsetDateTime' => '2024-09-23T16:38:00+00:00'
        }
      }

      parsed_allergy = adapter.parse_single_allergy(record)

      expect(parsed_allergy).not_to be_nil
      expect(parsed_allergy.date).to eq('2023-05-01T00:00:00+00:00')
      expect(StatsD).not_to have_received(:increment).with('unified_health_data.allergy.replace_date_with_onset')
    end

    it 'falls back to onsetDateTime when recordedDate is blank' do
      record = {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'allergy-with-onset-only',
          'clinicalStatus' => {
            'coding' => [{ 'code' => 'active' }]
          },
          'code' => {
            'text' => 'Pollen'
          },
          'recordedDate' => '',
          'onsetDateTime' => '2024-09-23T16:38:00+00:00'
        }
      }

      parsed_allergy = adapter.parse_single_allergy(record)

      expect(parsed_allergy).not_to be_nil
      expect(parsed_allergy.date).to eq('2024-09-23T16:38:00+00:00')
      expect(parsed_allergy.sort_date).to eq('2024-09-23T16:38:00+00:00')
    end

    it 'does not increment the fallback metric or return an empty string when both dates are blank' do
      allow(StatsD).to receive(:increment)

      record = {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'allergy-without-dates',
          'clinicalStatus' => {
            'coding' => [{ 'code' => 'active' }]
          },
          'code' => {
            'text' => 'Pollen'
          },
          'recordedDate' => '',
          'onsetDateTime' => ''
        }
      }

      parsed_allergy = adapter.parse_single_allergy(record)

      expect(parsed_allergy).not_to be_nil
      expect(parsed_allergy.date).to be_nil
      expect(StatsD).not_to have_received(:increment).with('unified_health_data.allergy.replace_date_with_onset')
    end
  end

  describe 'filter diagnostic logging' do
    let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
    let(:adapter_with_user) { UnifiedHealthData::Adapters::AllergyAdapter.new(user:) }

    let(:active_allergy) do
      {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'active-allergy',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'coding' => [{ 'display' => 'Peanut' }] }
        }
      }
    end

    let(:resolved_allergy) do
      {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'resolved-allergy',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'resolved' }] },
          'code' => { 'coding' => [{ 'display' => 'Penicillin' }] }
        }
      }
    end

    let(:missing_status_allergy) do
      {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'no-status-allergy',
          'code' => { 'coding' => [{ 'display' => 'Aspirin' }] }
        }
      }
    end

    before do
      allow(Flipper).to receive(:enabled?).and_return(false)
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medical_records_allergies_diagnostic, user)
        .and_return(true)
      allow(StatsD).to receive(:increment)
    end

    it 'logs diagnostic with inactive_clinical_status reason for resolved allergies' do
      expect(Rails.logger).to receive(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'allergies',
          action: 'filter',
          record_id: 'resolved-allergy',
          reason: 'inactive_clinical_status',
          log_level_context: 'diagnostic'
        )
      )

      adapter_with_user.parse([resolved_allergy])
    end

    it 'logs diagnostic with missing_clinical_status reason for allergies without status' do
      expect(Rails.logger).to receive(:info).with(
        hash_including(
          service: 'medical_records',
          resource: 'allergies',
          action: 'filter',
          record_id: 'no-status-allergy',
          reason: 'missing_clinical_status',
          log_level_context: 'diagnostic'
        )
      )

      adapter_with_user.parse([missing_status_allergy])
    end

    it 'increments StatsD counter with correct reason tag' do
      adapter_with_user.parse([resolved_allergy, missing_status_allergy])

      expect(StatsD).to have_received(:increment).with(
        'unified_health_data.allergy.filtered_record',
        tags: ['reason:inactive_clinical_status']
      )
      expect(StatsD).to have_received(:increment).with(
        'unified_health_data.allergy.filtered_record',
        tags: ['reason:missing_clinical_status']
      )
    end

    it 'does not log or increment for active allergies' do
      expect(Rails.logger).not_to receive(:info).with(
        hash_including(resource: 'allergies', action: 'filter')
      )
      expect(StatsD).not_to receive(:increment).with(
        'unified_health_data.allergy.filtered_record', anything
      )

      adapter_with_user.parse([active_allergy])
    end
  end

  # ==========================================================================
  # Null/nil exception regression tests (fixes 2a–2b)
  # ==========================================================================
  describe 'null/nil exception guards' do
    # 2a. extract_observed_historic — find returns nil
    describe '#parse_single_allergy — no allergyObservedHistoric extension (fix 2a)' do
      it 'returns nil observedHistoric when no matching extension found' do
        record = {
          'resource' => {
            'resourceType' => 'AllergyIntolerance',
            'id' => 'a-2a',
            'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
            'code' => { 'coding' => [{ 'display' => 'Peanut' }] },
            'extension' => [
              { 'url' => 'http://example.com/unrelated', 'valueCode' => 'test' }
            ]
          }
        }
        allergy = adapter.parse_single_allergy(record)
        expect(allergy.observedHistoric).to be_nil
      end

      it 'returns nil when extension array is empty' do
        record = {
          'resource' => {
            'resourceType' => 'AllergyIntolerance',
            'id' => 'a-2a-2',
            'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
            'code' => { 'coding' => [{ 'display' => 'Dust' }] },
            'extension' => []
          }
        }
        allergy = adapter.parse_single_allergy(record)
        expect(allergy.observedHistoric).to be_nil
      end
    end

    # 2b. find_contained — nil unless without return
    describe '#find_contained — return nil for mismatched type (fix 2b)' do
      it 'returns nil when contained resource has wrong type for hash reference' do
        record = {
          'contained' => [
            { 'id' => 'org-1', 'resourceType' => 'Organization', 'name' => 'VA Hospital' }
          ]
        }
        result = adapter.send(:find_contained, record, '#org-1', 'Location')
        expect(result).to be_nil
      end
    end
  end

  # Regression coverage for https://va.ghe.com/software/va.gov-team/issues/144840
  # VistA allergies only provide a recorder.reference (no inline display), pointing at a
  # sibling Practitioner entry elsewhere in the same SCDF response.
  describe 'VistA practitioner resolution (issue 144840)' do
    let(:vista_practitioner_resource) do
      {
        'resourceType' => 'Practitioner',
        'id' => 'b4b76108-25ba-44ca-b615-5396f577047d',
        'name' => [
          { 'family' => 'BORLAND', 'given' => ['VICTORIA'] }
        ]
      }
    end

    let(:vista_practitioner_entry) do
      { 'resource' => vista_practitioner_resource }
    end

    let(:vista_allergy_with_recorder_reference) do
      {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'vista-allergy-with-provider',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'PENICILLIN' },
          'recorder' => { 'reference' => 'Practitioner/b4b76108-25ba-44ca-b615-5396f577047d' }
        }
      }
    end

    it 'resolves the provider name from a sibling Practitioner entry via parse_single_allergy' do
      parsed_allergy = adapter.parse_single_allergy(
        vista_allergy_with_recorder_reference,
        practitioners: { vista_practitioner_resource['id'] => vista_practitioner_resource }
      )

      expect(parsed_allergy.provider).to eq('VICTORIA BORLAND')
    end

    it 'resolves the provider name end-to-end through parse when given the full record set' do
      parsed_allergies = adapter.parse([vista_allergy_with_recorder_reference, vista_practitioner_entry])

      expect(parsed_allergies.length).to eq(1)
      expect(parsed_allergies.first.provider).to eq('VICTORIA BORLAND')
    end

    it 'returns nil provider when the referenced Practitioner entry is not present' do
      parsed_allergy = adapter.parse_single_allergy(vista_allergy_with_recorder_reference)

      expect(parsed_allergy.provider).to be_nil
    end

    it 'does not raise and returns nil provider when recorder has no reference' do
      record = vista_allergy_with_recorder_reference.deep_dup
      record['resource'].delete('recorder')

      parsed_allergy = adapter.parse_single_allergy(record)

      expect(parsed_allergy.provider).to be_nil
    end

    it 'does not incorrectly resolve a provider via a nil id when a Practitioner entry has a blank id' do
      allergy_without_recorder = vista_allergy_with_recorder_reference.deep_dup
      allergy_without_recorder['resource'].delete('recorder')
      practitioner_with_blank_id = {
        'resource' => {
          'resourceType' => 'Practitioner',
          'id' => nil,
          'name' => [{ 'family' => 'BORLAND', 'given' => ['VICTORIA'] }]
        }
      }

      parsed_allergies = adapter.parse([allergy_without_recorder, practitioner_with_blank_id])

      expect(parsed_allergies.first.provider).to be_nil
    end

    it 'excludes Practitioner entries with a blank id from the lookup' do
      practitioner_with_blank_id = {
        'resource' => { 'resourceType' => 'Practitioner', 'id' => '', 'name' => [{ 'family' => 'DOE' }] }
      }

      lookup = adapter.send(:build_practitioner_lookup, [practitioner_with_blank_id, vista_practitioner_entry])

      expect(lookup).to eq({ vista_practitioner_resource['id'] => vista_practitioner_resource })
    end

    it 'falls back to an inline recorder.display when no Practitioner entry matches (Oracle Health)' do
      record = {
        'resource' => {
          'resourceType' => 'AllergyIntolerance',
          'id' => 'oh-allergy-with-display',
          'clinicalStatus' => { 'coding' => [{ 'code' => 'active' }] },
          'code' => { 'text' => 'LATEX' },
          'recorder' => { 'reference' => 'Practitioner/63662034', 'display' => 'Smith,John' }
        }
      }

      parsed_allergy = adapter.parse_single_allergy(record)

      expect(parsed_allergy.provider).to eq('John Smith')
    end
  end
end
