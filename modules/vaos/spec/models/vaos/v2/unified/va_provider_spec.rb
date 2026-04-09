# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::VAProvider do
  describe '#initialize' do
    it 'sets provider_type to va' do
      provider = described_class.new
      expect(provider.provider_type).to eq('va')
    end
  end

  describe '.from_facility_and_clinic' do
    let(:facility) do
      double(
        'FacilitiesApi::V2::Lighthouse::Facility',
        unique_id: '983',
        name: 'Cheyenne VA Medical Center',
        address: {
          'physical' => {
            'address1' => '2360 East Pershing Boulevard',
            'city' => 'Cheyenne',
            'state' => 'WY',
            'zip' => '82001'
          }
        },
        phone: { 'main' => '307-778-7550' },
        lat: 41.1456,
        long: -104.7892,
        facility_type: 'va_health_facility',
        services: {
          'health' => [
            { 'serviceId' => 'primaryCare' },
            { 'serviceId' => 'audiology' }
          ]
        }
      )
    end

    let(:clinic) do
      {
        id: '1014',
        station_id: '983',
        service_name: 'CHY AUDIOLOGY',
        physical_location: 'Main building'
      }
    end

    it 'sets id and name from the clinic payload and location_id from the facility' do
      provider = described_class.from_facility_and_clinic(facility, clinic)

      expect(provider.id).to eq('1014')
      expect(provider.location_id).to eq('983')
      expect(provider.facility_name).to eq('Cheyenne VA Medical Center')
      expect(provider.name).to eq('CHY AUDIOLOGY')
      expect(provider.provider_type).to eq('va')
    end

    it 'sets service_type when provided' do
      provider = described_class.from_facility_and_clinic(facility, clinic, service_type: 'audiology')

      expect(provider.service_type).to eq('audiology')
    end

    it 'defaults service_type to nil when not provided' do
      provider = described_class.from_facility_and_clinic(facility, clinic)

      expect(provider.service_type).to be_nil
    end

    it 'uses service_name for name' do
      provider = described_class.from_facility_and_clinic(
        facility,
        clinic.merge(service_name: 'PODIATRY CLINIC')
      )

      expect(provider.name).to eq('PODIATRY CLINIC')
    end

    it 'uses facility unique_id as location_id regardless of clinic station_id' do
      satellite_clinic = clinic.merge(station_id: '983GC', id: '945')

      provider = described_class.from_facility_and_clinic(facility, satellite_clinic)

      expect(provider.location_id).to eq('983')
      expect(provider.id).to eq('945')
    end

    it 'accepts OpenStruct clinic payloads' do
      provider = described_class.from_facility_and_clinic(
        facility,
        OpenStruct.new(clinic)
      )

      expect(provider.id).to eq('1014')
      expect(provider.name).to eq('CHY AUDIOLOGY')
    end

    it 'handles nil facility services gracefully' do
      allow(facility).to receive(:services).and_return(nil)

      provider = described_class.from_facility_and_clinic(facility, clinic)

      expect(provider.facility_name).to eq('Cheyenne VA Medical Center')
    end
  end
end
