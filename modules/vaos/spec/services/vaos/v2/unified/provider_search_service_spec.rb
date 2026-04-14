# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::ProviderSearchService do
  let(:user) { build(:user, :vaos) }
  let(:residential_address) do
    double('Address', latitude: 28.08, longitude: -80.60)
  end
  let(:vet360_contact_info) { double('Vet360ContactInfo', residential_address:) }
  let(:service) { described_class.new(user) }

  let(:referral) do
    double('Referral',
           category_of_care: 'UROLOGY',
           provider_npi: '91560381x')
  end

  let(:lighthouse_facility) do
    double(
      'Facility',
      id: 'vha_983',
      unique_id: '983',
      name: 'Cheyenne VA Medical Center',
      address: {
        'physical' => {
          'address1' => '2360 E Pershing Blvd', 'city' => 'Cheyenne',
          'state' => 'WY', 'zip' => '82001'
        }
      },
      phone: { 'main' => '307-778-7550', 'healthConnect' => '307-778-7550' },
      lat: 28.10,
      long: -80.62,
      facility_type: 'va_health_facility',
      services: { 'health' => [{ 'serviceId' => 'urology' }] }
    )
  end

  let(:eps_provider_hash) do
    {
      id: '9mN718pH',
      name: 'Dr. Bones @ Melbourne Medical',
      individual_providers: [{ name: 'Dr. Bones', npi: '91560381x' }],
      location: {
        address: '1105 Palmetto Ave, Melbourne, FL, 32901, US',
        latitude: 28.08061,
        longitude: -80.60322
      },
      network_ids: ['network-1'],
      specialties: [{ id: '208800000X', name: 'Urology' }],
      features: { is_digital: true, direct_booking: { is_enabled: true } }
    }
  end

  let(:urology_clinic) do
    OpenStruct.new(
      id: '455',
      station_id: '983',
      service_name: 'CHY UROLOGY',
      physical_location: nil
    )
  end

  let(:systems_service) { instance_double(VAOS::V2::SystemsService) }
  let(:eligibility_service) { instance_double(VAOS::V2::Unified::EligibilityService) }

  before do
    allow(user).to receive(:vet360_contact_info).and_return(vet360_contact_info)
  end

  describe '#search' do
    let(:lighthouse_client) { instance_double(FacilitiesApi::V2::Lighthouse::Client) }
    let(:eps_provider_service) { instance_double(Eps::ProviderService) }

    before do
      allow(FacilitiesApi::V2::Lighthouse::Client).to receive(:new).and_return(lighthouse_client)
      allow(Eps::ProviderService).to receive(:new).and_return(eps_provider_service)
      allow(VAOS::V2::SystemsService).to receive(:new).with(user).and_return(systems_service)
      allow(VAOS::V2::Unified::EligibilityService).to receive(:new).with(user).and_return(eligibility_service)
      allow(eligibility_service).to receive(:check_eligibility).and_return({ direct_eligible: true })

      allow(lighthouse_client).to receive(:get_facilities).and_return([lighthouse_facility])
      allow(eps_provider_service).to receive(:search_by_location).and_return([eps_provider_hash])
      allow(systems_service).to receive(:get_facility_clinics).and_return([urology_clinic])
    end

    it 'returns a combined list of VA clinics and EPS providers' do
      results = service.search(referral:)

      expect(results.size).to eq(2)
      provider_types = results.map(&:provider_type)
      expect(provider_types).to include('va', 'community_care')
      va = results.find { |p| p.provider_type == 'va' }
      expect(va.id).to eq('455')
      expect(va.location_id).to eq('983')
    end

    it 'pins the referral matched provider at the top' do
      results = service.search(referral:)

      first = results.first
      expect(first.provider_type).to eq('community_care')
      expect(first.npi).to eq('91560381x')
    end

    it 'computes distance for VA providers using haversine formula' do
      results = service.search(referral:)
      va_provider = results.find { |p| p.provider_type == 'va' }

      expect(va_provider.distance_from_user).to be_a(Float)
      expect(va_provider.distance_from_user).to be_positive
    end

    it 'sorts remaining providers by distance' do
      other_eps = eps_provider_hash.merge(
        id: 'other123',
        individual_providers: [{ name: 'Other', npi: '9999999' }],
        location: {
          address: '500 Far Ave, Orlando, FL, 32801, US',
          latitude: 28.5383,
          longitude: -81.3792
        }
      )
      allow(eps_provider_service).to receive(:search_by_location).and_return([eps_provider_hash, other_eps])

      results = service.search(referral:)

      expect(results.first.npi).to eq('91560381x')
      remaining = results.drop(1)
      distances = remaining.map(&:distance_from_user)
      expect(distances).to eq(distances.sort)
      expect(remaining.map(&:provider_type)).to eq(%w[va community_care])
    end

    it 'calls Lighthouse with correct parameters' do
      service.search(referral:, radius: 30)

      expect(lighthouse_client).to have_received(:get_facilities).with(
        hash_including(lat: 28.08, long: -80.60, radius: 30, type: 'health')
      )
    end

    it 'calls EPS with correct parameters' do
      service.search(referral:, radius: 30)

      expect(eps_provider_service).to have_received(:search_by_location).with(
        latitude: 28.08,
        longitude: -80.60,
        radius: 30,
        specialty: 'UROLOGY'
      )
    end

    it 'fetches VAOS clinics using ServiceTypeMapper.to_vaos(category_of_care)' do
      service.search(referral:)

      # UROLOGY is not in LIGHTHOUSE_TO_VAOS; mapper returns nil
      expect(systems_service).to have_received(:get_facility_clinics).with(
        location_id: '983',
        clinical_service: nil
      )
    end

    it 'passes mapped clinical service when category_of_care maps to VAOS' do
      audio_referral = double('Referral', category_of_care: 'audiology', provider_npi: '91560381x')

      service.search(referral: audio_referral)

      expect(systems_service).to have_received(:get_facility_clinics).with(
        location_id: '983',
        clinical_service: 'audiology'
      )
    end

    it 'raises error when user has no residential address' do
      allow(vet360_contact_info).to receive(:residential_address).and_return(nil)

      expect { service.search(referral:) }.to raise_error(Common::Exceptions::UnprocessableEntity)
    end

    it 'raises error when user address has no coordinates' do
      allow(residential_address).to receive(:latitude).and_return(nil)

      expect { service.search(referral:) }.to raise_error(Common::Exceptions::UnprocessableEntity)
    end

    it 'returns only EPS providers when Lighthouse fails' do
      allow(lighthouse_client).to receive(:get_facilities).and_raise(StandardError.new('timeout'))

      results = service.search(referral:)

      expect(results.size).to eq(1)
      expect(results.first.provider_type).to eq('community_care')
    end

    it 'returns only VA providers when EPS fails' do
      allow(eps_provider_service).to receive(:search_by_location).and_raise(StandardError.new('timeout'))

      results = service.search(referral:)

      expect(results.size).to eq(1)
      expect(results.first.provider_type).to eq('va')
    end

    it 'includes all facilities when category_of_care does not map to a VAOS service (no eligibility filter)' do
      non_matching_facility = double(
        'Facility',
        id: 'vha_984', unique_id: '984', name: 'Other VA',
        address: nil, phone: nil, lat: 28.12, long: -80.65,
        facility_type: 'va_health_facility',
        services: { 'health' => [{ 'serviceId' => 'podiatry' }] }
      )
      allow(lighthouse_client).to receive(:get_facilities).and_return(
        [lighthouse_facility, non_matching_facility]
      )

      results = service.search(referral:)

      va_providers = results.select { |p| p.provider_type == 'va' }
      expect(va_providers.size).to eq(2)
      expect(va_providers.map(&:location_id).sort).to eq(%w[983 984])
      expect(systems_service).to have_received(:get_facility_clinics).twice
      expect(eligibility_service).not_to have_received(:check_eligibility)
    end

    it 'excludes VA facilities that fail direct-scheduling eligibility when category maps to VAOS' do
      non_matching_facility = double(
        'Facility',
        id: 'vha_984', unique_id: '984', name: 'Other VA',
        address: nil, phone: nil, lat: 28.12, long: -80.65,
        facility_type: 'va_health_facility',
        services: { 'health' => [{ 'serviceId' => 'audiology' }] }
      )
      allow(lighthouse_client).to receive(:get_facilities).and_return(
        [lighthouse_facility, non_matching_facility]
      )
      audio_referral = double('Referral', category_of_care: 'audiology', provider_npi: '91560381x')

      allow(eligibility_service).to receive(:check_eligibility) do |facility_id:, category_of_care:|
        expect(category_of_care).to eq('audiology')
        {
          facility_id:,
          vaos_service_type: 'audiology',
          direct_eligible: facility_id == '983'
        }
      end

      results = service.search(referral: audio_referral)

      va_providers = results.select { |p| p.provider_type == 'va' }
      expect(va_providers.map(&:location_id)).to eq(['983'])
      expect(systems_service).to have_received(:get_facility_clinics).once
    end

    it 'returns no VA providers when get_facility_clinics returns no clinics' do
      allow(systems_service).to receive(:get_facility_clinics).and_return([])

      results = service.search(referral:)

      expect(results.map(&:provider_type)).to eq(['community_care'])
    end

    it 'uses the default 25-mile radius' do
      service.search(referral:)

      expect(lighthouse_client).to have_received(:get_facilities).with(
        hash_including(radius: 25)
      )
    end
  end
end
