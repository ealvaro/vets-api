# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::AppointmentSerializer do
  describe '#serialize' do
    context 'with care_type VA and Hash location (Mobile Facility–compatible shape)' do
      let(:appointment) do
        OpenStruct.new(
          id: 'va-appt-1',
          status: 'booked',
          start: '2026-04-15T14:00:00Z',
          past: false,
          modality: 'vaInPerson',
          service_name: 'CHY PC CASSIDY',
          location: {
            'name' => 'Cheyenne VA Medical Center',
            'timezone' => { 'zoneId' => 'America/Denver' },
            'lat' => 39.744507,
            'long' => -104.830956,
            'phone' => { 'main' => '307-778-7550' },
            'physicalAddress' => {
              'line' => ['2360 East Pershing Boulevard'],
              'city' => 'Cheyenne',
              'state' => 'WY',
              'postalCode' => '82001-5356'
            }
          }
        )
      end

      it 'maps facility into provider.location including timezone from zoneId' do
        json = described_class.new(appointment, care_type: 'VA').serialize
        tz = json.dig(:data, :attributes, :provider, :location, :timezone)

        expect(tz).to eq('America/Denver')
      end
    end

    context 'with care_type VA and OpenStruct location (string keys, betamocks-style timezone)' do
      let(:appointment) do
        facility = OpenStruct.new(
          'name' => 'Cheyenne VA Medical Center',
          'timezone' => { 'timeZoneId' => 'America/Denver' },
          'lat' => 39.744507,
          'long' => -104.830956,
          'phone' => OpenStruct.new('main' => '307-778-7550'),
          'physicalAddress' => {
            'line' => ['2360 East Pershing Boulevard'],
            'city' => 'Cheyenne',
            'state' => 'WY',
            'postalCode' => '82001-5356'
          }
        )
        OpenStruct.new(
          id: 'va-appt-2',
          status: 'booked',
          start: '2026-04-15T14:00:00Z',
          past: false,
          modality: 'vaInPerson',
          service_name: nil,
          location: facility
        )
      end

      it 'reads nested fields via fval for OpenStruct (string keys)' do
        json = described_class.new(appointment, care_type: 'VA').serialize
        provider = json.dig(:data, :attributes, :provider)

        expect(provider[:name]).to eq('Cheyenne VA Medical Center')
        expect(provider[:practice]).to eq('Cheyenne VA Medical Center')
        expect(provider[:phone]).to eq('307-778-7550')
        expect(provider[:location][:timezone]).to eq('America/Denver')
        expect(provider[:location][:address]).to eq('2360 East Pershing Boulevard, Cheyenne, WY, 82001-5356')
      end
    end

    context 'with care_type VA and OpenStruct location (symbol keys, time_zone_id)' do
      let(:appointment) do
        facility = OpenStruct.new(
          name: 'Cheyenne VA Medical Center',
          timezone: OpenStruct.new(time_zone_id: 'America/Denver'),
          lat: 39.744507,
          long: -104.830956,
          phone: { main: '307-778-7550' },
          physical_address: {
            line: ['2360 East Pershing Boulevard'],
            city: 'Cheyenne',
            state: 'WY',
            postal_code: '82001-5356'
          }
        )
        OpenStruct.new(
          id: 'va-appt-3',
          status: 'booked',
          start: '2026-04-15T14:00:00Z',
          past: false,
          modality: 'vaInPerson',
          service_name: 'Clinic display name',
          location: facility
        )
      end

      it 'extracts timezone from time_zone_id on nested OpenStruct' do
        json = described_class.new(appointment, care_type: 'VA').serialize
        tz = json.dig(:data, :attributes, :provider, :location, :timezone)

        expect(tz).to eq('America/Denver')
      end

      it 'prefers service_name over facility name for provider display name' do
        json = described_class.new(appointment, care_type: 'VA').serialize
        provider = json.dig(:data, :attributes, :provider)

        expect(provider[:name]).to eq('Clinic display name')
        expect(provider[:practice]).to eq('Cheyenne VA Medical Center')
      end
    end

    context 'with care_type VA and timezone nested hash using zone_id string key' do
      let(:appointment) do
        OpenStruct.new(
          id: 'va-appt-4',
          status: 'booked',
          start: '2026-04-15T14:00:00Z',
          past: false,
          modality: 'vaInPerson',
          service_name: nil,
          location: {
            'name' => 'Test Facility',
            'timezone' => { 'zone_id' => 'America/Chicago' }
          }
        )
      end

      it 'extracts timezone from zone_id' do
        json = described_class.new(appointment, care_type: 'VA').serialize

        expect(json.dig(:data, :attributes, :provider, :location, :timezone)).to eq('America/Chicago')
      end
    end

    context 'when facility lookup failed and location was replaced with the error sentinel' do
      let(:appointment) do
        OpenStruct.new(
          id: 'va-appt-err',
          status: 'booked',
          start: '2026-04-15T14:00:00Z',
          past: false,
          modality: 'vaInPerson',
          location_id: '983',
          location: VAOS::FacilityConstants::FACILITY_ERROR_MSG
        )
      end

      it 'sets facilityError and omits provider' do
        json = described_class.new(appointment, care_type: 'VA').serialize
        attrs = json.dig(:data, :attributes)

        expect(attrs[:facilityError]).to eq(VAOS::FacilityConstants::FACILITY_ERROR_MSG)
        expect(attrs[:provider]).to be_nil
      end
    end

    context 'with unsupported care_type' do
      let(:appointment) { OpenStruct.new(id: 'x') }

      it 'raises ArgumentError' do
        expect do
          described_class.new(appointment, care_type: 'OTHER').serialize
        end.to raise_error(ArgumentError, /Unsupported care_type/)
      end
    end
  end
end
