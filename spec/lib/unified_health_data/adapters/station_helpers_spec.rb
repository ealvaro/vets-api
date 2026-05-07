# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/station_helpers'

describe UnifiedHealthData::Adapters::StationHelpers do
  subject { helper_class.new }

  let(:helper_class) do
    Class.new do
      include UnifiedHealthData::Adapters::StationHelpers
    end
  end

  describe '#extract_station_number' do
    it 'extracts station number from SN= format' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => 'SN=668' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to eq('668')
    end

    it 'extracts station number from plain 3-digit format with OTHER type' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => '668' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to eq('668')
    end

    it 'prioritizes SN= format over plain format' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => '500' },
            { 'type' => { 'text' => 'OTHER' }, 'value' => 'SN=668' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to eq('668')
    end

    it 'falls back to Organization when no Practitioner exists' do
      contained = [
        {
          'resourceType' => 'Organization',
          'id' => 'org-123',
          'identifier' => [
            { 'use' => 'usual', 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '989' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to eq('989')
    end

    it 'returns nil when neither Practitioner nor Organization have valid identifiers' do
      contained = [
        { 'resourceType' => 'Practitioner', 'id' => 'prac-1' },
        { 'resourceType' => 'Organization', 'id' => 'org-1', 'name' => 'Test Lab' }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to be_nil
    end

    it 'returns nil when Practitioner has no identifiers' do
      contained = [
        { 'resourceType' => 'Practitioner', 'id' => 'prac-123' }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to be_nil
    end

    it 'returns nil when contained is blank' do
      expect(subject.extract_station_number(nil)).to be_nil
      expect(subject.extract_station_number([])).to be_nil
    end

    it 'extracts station number with letter suffix from OTHER identifier' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => '668A' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to eq('668A')
    end

    it 'extracts station number with two-letter suffix from OTHER identifier' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => '668GC' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to eq('668GC')
    end

    it 'ignores identifiers with more than 2 letter suffix' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => '668ABC' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to be_nil
    end

    it 'ignores non-station-number OTHER identifiers' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => '1000690375' },
            { 'type' => { 'text' => 'Messaging' }, 'value' => '8305155' }
          ]
        }
      ]

      result = subject.extract_station_number(contained)
      expect(result).to be_nil
    end

    context 'with Organization fallback (VistA data)' do
      it 'extracts station number from Organization with VA OID system' do
        contained = [
          {
            'resourceType' => 'Organization',
            'id' => 'org-123',
            'identifier' => [
              { 'use' => 'usual', 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '989' }
            ],
            'name' => 'CHYSHR TEST LAB'
          }
        ]

        result = subject.extract_station_number(contained)
        expect(result).to eq('989')
      end

      it 'returns nil when Organization has no VA OID identifier' do
        contained = [
          {
            'resourceType' => 'Organization',
            'id' => 'org-123',
            'identifier' => [
              { 'use' => 'usual', 'system' => 'some-other-system', 'value' => '123' }
            ],
            'name' => 'Test Lab'
          }
        ]

        result = subject.extract_station_number(contained)
        expect(result).to be_nil
      end

      it 'prioritizes Practitioner over Organization' do
        contained = [
          {
            'resourceType' => 'Practitioner',
            'id' => 'prac-123',
            'identifier' => [
              { 'type' => { 'text' => 'OTHER' }, 'value' => 'SN=668' }
            ]
          },
          {
            'resourceType' => 'Organization',
            'id' => 'org-123',
            'identifier' => [
              { 'use' => 'usual', 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '989' }
            ]
          }
        ]

        result = subject.extract_station_number(contained)
        expect(result).to eq('668')
      end

      it 'falls back to Organization when Practitioner has no station number' do
        contained = [
          {
            'resourceType' => 'Practitioner',
            'id' => 'prac-123',
            'identifier' => [
              { 'extension' => [{ 'url' => 'http://hl7.org/fhir/StructureDefinition/data-absent-reason',
                                  'valueCode' => 'unknown' }] }
            ]
          },
          {
            'resourceType' => 'Organization',
            'id' => 'org-123',
            'identifier' => [
              { 'use' => 'usual', 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '989' }
            ]
          }
        ]

        result = subject.extract_station_number(contained)
        expect(result).to eq('989')
      end

      it 'falls back to Organization when no Practitioner exists' do
        contained = [
          {
            'resourceType' => 'Organization',
            'id' => 'org-123',
            'identifier' => [
              { 'use' => 'usual', 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '500' }
            ]
          },
          { 'resourceType' => 'ServiceRequest', 'id' => 'sr-1' }
        ]

        result = subject.extract_station_number(contained)
        expect(result).to eq('500')
      end
    end
  end

  describe '#extract_station_number_from_record' do
    it 'extracts station number from a full record structure' do
      record = {
        'resource' => {
          'contained' => [
            {
              'resourceType' => 'Practitioner',
              'identifier' => [
                { 'type' => { 'text' => 'OTHER' }, 'value' => 'SN=668' }
              ]
            }
          ]
        }
      }

      result = subject.extract_station_number_from_record(record)
      expect(result).to eq('668')
    end

    it 'returns nil when record has no contained resources' do
      record = { 'resource' => {} }
      result = subject.extract_station_number_from_record(record)
      expect(result).to be_nil
    end

    it 'returns nil when record is nil' do
      result = subject.extract_station_number_from_record(nil)
      expect(result).to be_nil
    end
  end

  describe '#extract_station_from_practitioner' do
    it 'extracts station number from SN= format' do
      contained = [
        {
          'resourceType' => 'Practitioner',
          'id' => 'prac-123',
          'identifier' => [
            { 'type' => { 'text' => 'OTHER' }, 'value' => 'SN=668' }
          ]
        }
      ]

      result = subject.extract_station_from_practitioner(contained)
      expect(result).to eq('668')
    end

    it 'returns nil when no Practitioner exists' do
      contained = [{ 'resourceType' => 'Organization', 'id' => 'org-1' }]
      result = subject.extract_station_from_practitioner(contained)
      expect(result).to be_nil
    end
  end

  describe '#extract_station_from_organization' do
    it 'extracts station number from Organization with VA OID system' do
      contained = [
        {
          'resourceType' => 'Organization',
          'id' => 'org-123',
          'identifier' => [
            { 'use' => 'usual', 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '989' }
          ]
        }
      ]

      result = subject.extract_station_from_organization(contained)
      expect(result).to eq('989')
    end

    it 'returns nil when Organization has no identifiers' do
      contained = [
        { 'resourceType' => 'Organization', 'id' => 'org-123', 'name' => 'Test Lab' }
      ]

      result = subject.extract_station_from_organization(contained)
      expect(result).to be_nil
    end

    it 'returns nil when no Organization exists' do
      contained = [{ 'resourceType' => 'Practitioner', 'id' => 'prac-1' }]
      result = subject.extract_station_from_organization(contained)
      expect(result).to be_nil
    end

    it 'ignores identifiers without VA OID system' do
      contained = [
        {
          'resourceType' => 'Organization',
          'id' => 'org-123',
          'identifier' => [
            { 'system' => 'http://some-other-system.com', 'value' => '12345' }
          ]
        }
      ]

      result = subject.extract_station_from_organization(contained)
      expect(result).to be_nil
    end
  end

  describe '#resolve_hostname_location' do
    let(:facility_name_resolver) { instance_double(UnifiedHealthData::Adapters::FacilityNameResolver) }

    before do
      allow(UnifiedHealthData::Adapters::FacilityNameResolver).to receive(:new).and_return(facility_name_resolver)
    end

    it 'returns facility name when organization has VA OID identifier' do
      organization = {
        'id' => 'org-1',
        'identifier' => [
          { 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '668' }
        ]
      }

      allow(facility_name_resolver).to receive(:lookup).with('668').and_return('Mann-Grandstaff VA Medical Center')

      result = subject.resolve_hostname_location(organization)
      expect(result).to eq('Mann-Grandstaff VA Medical Center')
    end

    it 'returns nil when organization has no VA OID identifier' do
      organization = {
        'id' => 'org-1',
        'identifier' => [
          { 'system' => 'http://other-system.com', 'value' => '123' }
        ]
      }

      result = subject.resolve_hostname_location(organization)
      expect(result).to be_nil
    end

    it 'returns nil when organization has no identifiers' do
      organization = { 'id' => 'org-1', 'name' => 'Test Org' }

      result = subject.resolve_hostname_location(organization)
      expect(result).to be_nil
    end

    it 'returns nil when organization is nil' do
      result = subject.resolve_hostname_location(nil)
      expect(result).to be_nil
    end

    it 'returns nil and logs warning when resolver raises an error' do
      organization = {
        'id' => 'org-1',
        'identifier' => [
          { 'system' => 'urn:oid:2.16.840.1.113883.4.349', 'value' => '668' }
        ]
      }

      allow(facility_name_resolver).to receive(:lookup).and_raise(StandardError.new('lookup failed'))
      allow(Rails.logger).to receive(:warn)

      result = subject.resolve_hostname_location(organization)
      expect(result).to be_nil
    end
  end
end
