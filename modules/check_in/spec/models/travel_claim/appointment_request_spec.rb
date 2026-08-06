# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelClaim::AppointmentRequest do
  subject(:request) do
    described_class.new(
      appointment_date_time:,
      station_number:,
      facility_name:
    )
  end

  let(:appointment_date_time) { '2024-01-01T12:00:00Z' }
  let(:station_number) { '500' }
  let(:facility_name) { 'Test VA Medical Center' }

  describe '#to_h' do
    it 'builds the BTSSS find-or-add appointment body' do
      expect(request.to_h).to eq(
        appointmentDateTime: appointment_date_time,
        facilityStationNumber: station_number,
        facilityName: facility_name,
        appointmentName: "#{facility_name} #{appointment_date_time}"
      )
    end

    context 'when the facility name would make the appointment name too long' do
      let(:facility_name) { 'A' * 120 }

      it 'truncates the facility name and preserves the full datetime' do
        appointment_name = request.to_h[:appointmentName]

        expect(appointment_name.length).to eq(100)
        expect(appointment_name).to end_with(" #{appointment_date_time}")
      end
    end
  end
end
