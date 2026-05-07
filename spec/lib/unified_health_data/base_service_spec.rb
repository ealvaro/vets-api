# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/base_service'
require 'support/shared_contexts/uhd_security_endpoint'

describe UnifiedHealthData::BaseService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  subject { described_class }

  include_context 'uhd legacy security endpoint'

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:service) { described_class.new(user) }

  describe '#fetch_combined_records' do
    context 'when body is nil' do
      it 'returns an empty array' do
        result = service.send(:fetch_combined_records, nil)

        expect(result).to eq([])
      end
    end

    context 'when body has VistA and Oracle Health records' do
      let(:body) do
        {
          'vista' => {
            'entry' => [
              { 'resource' => { 'id' => 'vista-1', 'resourceType' => 'DiagnosticReport' } }
            ]
          },
          'oracle-health' => {
            'entry' => [
              { 'resource' => { 'id' => 'oracle-1', 'resourceType' => 'DiagnosticReport' } }
            ]
          }
        }
      end

      it 'adds source to each record and combines them' do
        result = service.send(:fetch_combined_records, body)
        expect(result.size).to eq(2)
        vista_record = result.find { |r| r['resource']['id'] == 'vista-1' }
        oracle_record = result.find { |r| r['resource']['id'] == 'oracle-1' }
        expect(vista_record['source']).to eq('vista')
        expect(oracle_record['source']).to eq('oracle-health')
      end
    end
  end

  describe '#validate_icn!' do
    context 'when user has nil ICN' do
      let(:service_without_icn) { described_class.new(build(:user, :loa3, icn: nil)) }

      it 'raises ParameterMissing' do
        expect { service_without_icn.send(:validate_icn!) }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end
    end

    context 'when user has empty string ICN' do
      let(:service_with_empty_icn) { described_class.new(build(:user, :loa3, icn: '')) }

      it 'raises ParameterMissing' do
        expect { service_with_empty_icn.send(:validate_icn!) }
          .to raise_error(Common::Exceptions::ParameterMissing) { |e|
            expect(e.param).to eq('ICN')
          }
      end
    end

    context 'when user is nil' do
      let(:nil_user_service) { described_class.new(nil) }

      it 'raises ParameterMissing' do
        expect { nil_user_service.send(:validate_icn!) }
          .to raise_error(Common::Exceptions::ParameterMissing)
      end
    end

    context 'when user has valid ICN' do
      it 'does not raise' do
        expect { service.send(:validate_icn!) }.not_to raise_error
      end
    end
  end

  # ------------------------------------------------------------------
  # Private helper method specs
  # ------------------------------------------------------------------

  describe '#extract_all_entries' do
    it 'extracts resource hashes from a FHIR Bundle entry array' do
      bundle = {
        'entry' => [
          { 'resource' => { 'id' => '1', 'resourceType' => 'AllergyIntolerance' } },
          { 'resource' => { 'id' => '2', 'resourceType' => 'AllergyIntolerance' } }
        ]
      }

      result = service.send(:extract_all_entries, bundle)

      expect(result.size).to eq(2)
      expect(result.first['id']).to eq('1')
      expect(result.last['id']).to eq('2')
    end

    it 'extracts from a nested resource wrapper' do
      bundle = {
        'resource' => {
          'entry' => [
            { 'resource' => { 'id' => '1' } }
          ]
        }
      }

      result = service.send(:extract_all_entries, bundle)

      expect(result).to eq([{ 'id' => '1' }])
    end

    it 'returns empty array when bundle is not a Hash' do
      expect(service.send(:extract_all_entries, nil)).to eq([])
      expect(service.send(:extract_all_entries, 'invalid')).to eq([])
    end

    it 'returns empty array when entries is not an Array' do
      expect(service.send(:extract_all_entries, { 'entry' => nil })).to eq([])
    end

    it 'filters out entries without a resource key' do
      bundle = {
        'entry' => [
          { 'resource' => { 'id' => '1' } },
          { 'other' => 'data' }
        ]
      }

      result = service.send(:extract_all_entries, bundle)

      expect(result).to eq([{ 'id' => '1' }])
    end
  end

  describe '#extract_bundle' do
    it 'finds a resource by resourceType from a Bundle' do
      body = {
        'entry' => [
          { 'resource' => { 'resourceType' => 'Patient', 'id' => 'p1' } },
          { 'resource' => { 'resourceType' => 'AllergyIntolerance', 'id' => 'a1' } }
        ]
      }

      result = service.send(:extract_bundle, body, 'AllergyIntolerance')

      expect(result).to eq({ 'resourceType' => 'AllergyIntolerance', 'id' => 'a1' })
    end

    it 'returns nil when resourceType is not found' do
      body = {
        'entry' => [
          { 'resource' => { 'resourceType' => 'Patient', 'id' => 'p1' } }
        ]
      }

      expect(service.send(:extract_bundle, body, 'Condition')).to be_nil
    end

    it 'returns nil when body is not a Hash' do
      expect(service.send(:extract_bundle, nil, 'Patient')).to be_nil
    end

    it 'returns nil when entries is not an Array' do
      expect(service.send(:extract_bundle, { 'entry' => nil }, 'Patient')).to be_nil
    end
  end

  describe '#extract_warnings' do
    it 'returns warnings from the body and removes them' do
      body = {
        'vista' => { 'entry' => [] },
        '_warnings' => [{ 'source' => 'oracle-health', 'code' => 'not-found' }]
      }

      warnings = service.send(:extract_warnings, body)

      expect(warnings).to eq([{ 'source' => 'oracle-health', 'code' => 'not-found' }])
      expect(body).not_to have_key('_warnings')
    end

    it 'returns empty array when body has no _warnings key' do
      body = { 'vista' => { 'entry' => [] } }

      expect(service.send(:extract_warnings, body)).to eq([])
    end

    it 'returns empty array when body is nil' do
      expect(service.send(:extract_warnings, nil)).to eq([])
    end

    it 'returns empty array when body is not a Hash' do
      expect(service.send(:extract_warnings, 'invalid')).to eq([])
    end
  end

  describe '#validate_date_param' do
    it 'does not raise for a valid YYYY-MM-DD date string' do
      expect { service.send(:validate_date_param, '2024-06-15', 'start_date') }.not_to raise_error
    end

    it 'raises ArgumentError for an invalid date string' do
      expect do
        service.send(:validate_date_param, 'not-a-date', 'start_date')
      end.to raise_error(ArgumentError, /Invalid start_date/)
    end

    it 'raises ArgumentError for nil date' do
      expect do
        service.send(:validate_date_param, nil, 'end_date')
      end.to raise_error(ArgumentError, /Invalid end_date/)
    end
  end

  describe '#normalize_date_range' do
    it 'returns provided dates when both are valid' do
      result = service.send(:normalize_date_range, '2023-01-01', '2024-12-31')

      expect(result).to eq(%w[2023-01-01 2024-12-31])
    end

    it 'uses default start date when start_date is nil' do
      result = service.send(:normalize_date_range, nil, '2024-12-31')

      expect(result).to eq(%w[1900-01-01 2024-12-31])
    end

    it 'uses default end date when end_date is nil' do
      result = service.send(:normalize_date_range, '2023-01-01', nil)

      expect(result).to eq(['2023-01-01', Time.zone.today.to_s])
    end

    it 'uses both defaults when both are blank' do
      result = service.send(:normalize_date_range, '', '')

      expect(result).to eq(['1900-01-01', Time.zone.today.to_s])
    end

    it 'raises ArgumentError for invalid start_date' do
      expect do
        service.send(:normalize_date_range, 'bad-date', '2024-12-31')
      end.to raise_error(ArgumentError, /Invalid start_date/)
    end

    it 'raises ArgumentError for invalid end_date' do
      expect do
        service.send(:normalize_date_range, '2023-01-01', 'bad-date')
      end.to raise_error(ArgumentError, /Invalid end_date/)
    end
  end

  describe '#remap_vista_uid' do
    it 'remaps VistA note IDs based on vista-uid identifier' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-id',
                'identifier' => [
                  { 'system' => 'vista-uid', 'value' => 'urn:va:note:500:12345:6789' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_uid, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('500-12345-6789')
    end

    it 'does not remap when no vista-uid identifier is present' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-id',
                'identifier' => [
                  { 'system' => 'other-system', 'value' => 'some-value' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_uid, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('original-id')
    end

    it 'handles entries without identifiers' do
      records = {
        'vista' => {
          'entry' => [
            { 'resource' => { 'id' => 'original-id' } }
          ]
        }
      }

      expect { service.send(:remap_vista_uid, records) }.not_to raise_error
      expect(records['vista']['entry'].first['resource']['id']).to eq('original-id')
    end
  end

  describe '#remap_vista_identifier' do
    it 'remaps VistA allergy IDs based on va.gov systems identifier' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-allergy-id',
                'identifier' => [
                  { 'system' => 'https://va.gov/systems/mhv', 'value' => 'remapped-id-123' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_identifier, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('remapped-id-123')
    end

    it 'does not remap when no matching identifier is present' do
      records = {
        'vista' => {
          'entry' => [
            {
              'resource' => {
                'id' => 'original-allergy-id',
                'identifier' => [
                  { 'system' => 'http://other.system/id', 'value' => 'other-value' }
                ]
              }
            }
          ]
        }
      }

      service.send(:remap_vista_identifier, records)

      expect(records['vista']['entry'].first['resource']['id']).to eq('original-allergy-id')
    end

    it 'handles entries without identifiers' do
      records = {
        'vista' => {
          'entry' => [
            { 'resource' => { 'id' => 'original-allergy-id' } }
          ]
        }
      }

      expect { service.send(:remap_vista_identifier, records) }.not_to raise_error
      expect(records['vista']['entry'].first['resource']['id']).to eq('original-allergy-id')
    end
  end

  describe '#default_start_date and #default_end_date' do
    it 'returns 1900-01-01 as default start date' do
      expect(service.send(:default_start_date)).to eq('1900-01-01')
    end

    it 'returns today as default end date' do
      expect(service.send(:default_end_date)).to eq(Time.zone.today.to_s)
    end
  end
end
