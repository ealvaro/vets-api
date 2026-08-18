# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::UnifiedProviderSerializer do
  subject(:serializer) { described_class.new }

  let(:va_provider) do
    VAOS::V2::Unified::VAProvider.new(
      id: '1081',
      location_id: '983',
      name: 'CHY AUDIOLOGY',
      facility_name: 'Cheyenne VA Medical Center',
      address: { street1: '2360 E Pershing Blvd', city: 'Cheyenne', state: 'WY', zip: '82001' },
      phone: '307-778-7550',
      latitude: 41.1456,
      longitude: -104.7892,
      distance_from_user: 3.24
    )
  end

  let(:eps_provider) do
    VAOS::V2::Unified::EpsProvider.new(
      id: '9mN718pH',
      name: 'Dr. Bones @ Melbourne Medical',
      facility_name: 'Melbourne Medical',
      address: { street1: '1105 Palmetto Ave', city: 'Melbourne', state: 'FL', zip: '32901' },
      phone: '555-555-0001',
      latitude: 28.08061,
      longitude: -80.60322,
      npi: '91560381x',
      distance_from_user: 2.1
    )
  end

  describe '#serialize' do
    it 'returns an array of serialized providers' do
      result = serializer.serialize([va_provider, eps_provider])

      expect(result.size).to eq(2)
      expect(result.first[:type]).to eq('unified_provider')
      expect(result.last[:type]).to eq('unified_provider')
    end

    it 'serializes VA provider attributes' do
      result = serializer.serialize([va_provider]).first

      expect(result[:id]).to eq('1081')
      expect(result[:attributes][:name]).to eq('CHY AUDIOLOGY')
      expect(result[:attributes][:facilityName]).to eq('Cheyenne VA Medical Center')
      expect(result[:attributes][:providerType]).to eq('va')
      expect(result[:attributes][:distanceInMiles]).to eq(3.2)
    end

    context 'facilityType (round-tripped to FE for slots requests)' do
      it 'is included when present so the FE can echo it back on the slots request' do
        va_provider.facility_type = 'va_cerner_facility'
        result = serializer.serialize([va_provider]).first

        expect(result[:attributes][:facilityType]).to eq('va_cerner_facility')
      end

      it 'is omitted (not nil) when the provider has no facility_type' do
        result = serializer.serialize([va_provider]).first

        expect(result[:attributes]).not_to have_key(:facilityType)
      end

      it 'is not added to EPS providers' do
        result = serializer.serialize([eps_provider]).first

        expect(result[:attributes]).not_to have_key(:facilityType)
      end
    end

    it 'serializes EPS provider attributes' do
      result = serializer.serialize([eps_provider]).first

      expect(result[:id]).to eq('9mN718pH')
      expect(result[:attributes][:name]).to eq('Dr. Bones @ Melbourne Medical')
      expect(result[:attributes][:facilityName]).to eq('Melbourne Medical')
      expect(result[:attributes][:providerType]).to eq('eps')
      expect(result[:attributes]).not_to have_key(:locationId)
      expect(result[:attributes]).not_to have_key(:clinicId)
    end

    it 'marks the referral provider correctly' do
      result = serializer.serialize([eps_provider], referral_npi: '91560381x').first

      expect(result[:attributes][:isReferralProvider]).to be true
    end

    it 'does not mark non-referral providers' do
      result = serializer.serialize([va_provider], referral_npi: '91560381x').first

      expect(result[:attributes][:isReferralProvider]).to be false
    end

    it 'serializes address structure with all street lines' do
      result = serializer.serialize([va_provider]).first

      expect(result[:attributes][:address]).to eq({
                                                    street1: '2360 E Pershing Blvd',
                                                    street2: nil,
                                                    street3: nil,
                                                    city: 'Cheyenne',
                                                    state: 'WY',
                                                    zip: '82001'
                                                  })
    end

    it 'includes sort order' do
      result = serializer.serialize([va_provider, eps_provider])

      expect(result[0][:attributes][:sortOrder]).to eq(0)
      expect(result[1][:attributes][:sortOrder]).to eq(1)
    end

    context 'onlineScheduling (post-MVP)' do
      it 'is omitted by default (flag off)' do
        result = serializer.serialize([va_provider, eps_provider])

        expect(result.first[:attributes]).not_to have_key(:onlineScheduling)
        expect(result.last[:attributes]).not_to have_key(:onlineScheduling)
      end

      it 'adds the onlineScheduling key to every provider when include_online_scheduling is true' do
        result = serializer.serialize([va_provider, eps_provider], include_online_scheduling: true)

        expect(result).to all(satisfy { |p| p[:attributes].key?(:onlineScheduling) })
      end

      it 'reflects the EPS provider digital-booking features' do
        eps_provider.digital_booking_features = { is_digital: true, direct_booking: { is_enabled: false } }
        result = serializer.serialize([eps_provider], include_online_scheduling: true).first

        expect(result[:attributes][:onlineScheduling]).to be false
      end

      it 'is true for VA providers (always direct-eligible)' do
        result = serializer.serialize([va_provider], include_online_scheduling: true).first

        expect(result[:attributes][:onlineScheduling]).to be true
      end
    end

    context 'nextAvailableDate' do
      it 'emits nextAvailableDate when populated on a VA provider' do
        va_provider.next_available_date = '2026-06-10'
        result = serializer.serialize([va_provider]).first

        expect(result[:attributes][:nextAvailableDate]).to eq('2026-06-10')
      end

      it 'emits nextAvailableDate as nil for VA providers without enrichment' do
        result = serializer.serialize([va_provider]).first

        expect(result[:attributes]).to have_key(:nextAvailableDate)
        expect(result[:attributes][:nextAvailableDate]).to be_nil
      end

      it 'emits nextAvailableDate when populated on an EPS provider' do
        eps_provider.next_available_date = '2026-06-15'
        result = serializer.serialize([eps_provider]).first

        expect(result[:attributes][:nextAvailableDate]).to eq('2026-06-15')
      end

      it 'emits nextAvailableDate as nil for EPS providers without enrichment (flag off / no slots)' do
        result = serializer.serialize([eps_provider]).first

        expect(result[:attributes]).to have_key(:nextAvailableDate)
        expect(result[:attributes][:nextAvailableDate]).to be_nil
      end
    end

    context 'driveTime' do
      it 'emits driveTime and driveTimeInSeconds when populated on an EPS provider' do
        eps_provider.drive_time_in_seconds = 420
        result = serializer.serialize([eps_provider]).first

        expect(result[:attributes][:driveTimeInSeconds]).to eq(420)
        expect(result[:attributes][:driveTime]).to eq('7 minute drive')
      end

      it 'omits both keys (proper nil) for VA providers, which are not enriched in this phase' do
        result = serializer.serialize([va_provider]).first

        expect(result[:attributes]).not_to have_key(:driveTime)
        expect(result[:attributes]).not_to have_key(:driveTimeInSeconds)
      end

      it 'omits both keys for an EPS provider without drive-time enrichment' do
        result = serializer.serialize([eps_provider]).first

        expect(result[:attributes]).not_to have_key(:driveTime)
        expect(result[:attributes]).not_to have_key(:driveTimeInSeconds)
      end

      it 'formats the drive time across minute/hour boundaries' do
        {
          30 => '1 minute drive', # sub-minute floors to 1
          59 => '1 minute drive',
          420 => '7 minute drive',
          3600 => '1 hour drive',
          3660 => '1 hour and 1 minute drive'
        }.each do |seconds, expected|
          eps_provider.drive_time_in_seconds = seconds
          result = serializer.serialize([eps_provider]).first

          expect(result[:attributes][:driveTime]).to eq(expected)
        end
      end
    end
  end
end
