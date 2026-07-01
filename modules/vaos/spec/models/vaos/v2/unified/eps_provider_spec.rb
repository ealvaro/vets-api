# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::EpsProvider do
  describe '#initialize' do
    it 'sets provider_type to eps' do
      provider = described_class.new
      expect(provider.provider_type).to eq('eps')
    end
  end

  describe '.from_eps_provider_service' do
    let(:eps_provider) do
      {
        id: '9mN718pH',
        name: 'Dr. Bones @ FHA South Melbourne Medical Complex',
        individual_providers: [
          { name: 'Dr. Bones', npi: '91560381x' }
        ],
        provider_organization: { name: 'Meridian Health' },
        location: {
          name: 'FHA South Melbourne Medical Complex',
          address: '1105 Palmetto Ave, Melbourne, FL, 32901, US',
          latitude: 28.08061,
          longitude: -80.60322,
          timezone: 'America/New_York'
        },
        network_ids: ['sandboxnetwork-5vuTac8v'],
        contact_details: [
          { system: 'phone', use: 'for_patient', value: '555-555-0001' }
        ],
        specialties: [
          { id: '208800000X', name: 'Urology' }
        ],
        features: {
          is_digital: true,
          direct_booking: { is_enabled: true }
        },
        appointment_types: [
          { id: 'ov', is_self_schedulable: true }
        ]
      }
    end

    it 'maps EPS provider fields to EpsProvider' do
      provider = described_class.from_eps_provider_service(eps_provider)

      expect(provider.id).to eq('9mN718pH')
      expect(provider.provider_service_id).to eq('9mN718pH')
      expect(provider.name).to eq('Dr. Bones @ FHA South Melbourne Medical Complex')
      expect(provider.provider_type).to eq('eps')
      expect(provider.latitude).to eq(28.08061)
      expect(provider.longitude).to eq(-80.60322)
      expect(provider.phone).to eq('555-555-0001')
      expect(provider.npi).to eq('91560381x')
      expect(provider.network_id).to eq('sandboxnetwork-5vuTac8v')
      expect(provider.specialties).to eq([{ id: '208800000X', name: 'Urology' }])
      expect(provider.facility_name).to eq('FHA South Melbourne Medical Complex')
      expect(provider.appointment_types).to eq([{ id: 'ov', is_self_schedulable: true }])
      expect(provider.address).to eq({
                                       street1: '1105 Palmetto Ave',
                                       city: 'Melbourne',
                                       state: 'FL',
                                       zip: '32901'
                                     })
    end

    it 'works with OpenStruct input' do
      provider = described_class.from_eps_provider_service(OpenStruct.new(eps_provider))

      expect(provider.id).to eq('9mN718pH')
      expect(provider.provider_type).to eq('eps')
    end

    it 'handles missing contact details' do
      eps_provider[:contact_details] = nil
      provider = described_class.from_eps_provider_service(eps_provider)

      expect(provider.phone).to be_nil
    end

    it 'handles missing individual providers' do
      eps_provider[:individual_providers] = nil
      provider = described_class.from_eps_provider_service(eps_provider)

      expect(provider.npi).to be_nil
    end

    it 'uses provider name as facility_name when location has no name' do
      eps_provider[:location] = eps_provider[:location].except(:name)
      provider = described_class.from_eps_provider_service(eps_provider)

      expect(provider.facility_name).to eq('Dr. Bones @ FHA South Melbourne Medical Complex')
    end

    it 'defaults appointment_types to empty when omitted' do
      eps_provider.delete(:appointment_types)
      provider = described_class.from_eps_provider_service(eps_provider)

      expect(provider.appointment_types).to eq([])
    end
  end

  describe '#online_scheduling?' do
    it 'is true when the provider is digital and direct booking is enabled' do
      provider = described_class.new(
        digital_booking_features: { is_digital: true, direct_booking: { is_enabled: true } }
      )

      expect(provider.online_scheduling?).to be true
    end

    it 'is false when direct booking is disabled (phone-only)' do
      provider = described_class.new(
        digital_booking_features: { is_digital: true, direct_booking: { is_enabled: false } }
      )

      expect(provider.online_scheduling?).to be false
    end

    it 'is false when the provider is not digital' do
      provider = described_class.new(
        digital_booking_features: { is_digital: false, direct_booking: { is_enabled: true } }
      )

      expect(provider.online_scheduling?).to be false
    end

    it 'is false when digital booking features are absent' do
      provider = described_class.new

      expect(provider.online_scheduling?).to be false
    end

    it 'reflects the features mapped from an EPS provider service response' do
      provider = described_class.from_eps_provider_service(
        id: 'abc',
        name: 'Phone Only Clinic',
        features: { is_digital: false, direct_booking: { is_enabled: false } }
      )

      expect(provider.online_scheduling?).to be false
    end
  end

  describe '#first_self_schedulable_appointment_type_id!' do
    it 'returns the first self-schedulable type id' do
      provider = described_class.new(
        appointment_types: [
          { id: 'phone', is_self_schedulable: false },
          { id: 'ov', is_self_schedulable: true }
        ]
      )

      expect(provider.first_self_schedulable_appointment_type_id!).to eq('ov')
    end

    it 'raises when appointment_types is blank' do
      provider = described_class.new(appointment_types: [])

      expect { provider.first_self_schedulable_appointment_type_id! }
        .to raise_error(Common::Exceptions::BackendServiceException)
    end

    it 'raises when no self-schedulable types exist' do
      provider = described_class.new(
        appointment_types: [{ id: 'phone', is_self_schedulable: false }]
      )

      expect { provider.first_self_schedulable_appointment_type_id! }
        .to raise_error(Common::Exceptions::BackendServiceException)
    end
  end
end
