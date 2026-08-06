# frozen_string_literal: true

module TravelClaim
  class AppointmentRequest
    APPOINTMENT_NAME_MAX_LENGTH = 100

    def initialize(appointment_date_time:, station_number:, facility_name:)
      @appointment_date_time = appointment_date_time
      @station_number = station_number
      @facility_name = facility_name
    end

    def to_h
      {
        appointmentDateTime: @appointment_date_time,
        facilityStationNumber: @station_number,
        facilityName: @facility_name,
        appointmentName: appointment_name
      }
    end

    private

    def appointment_name
      facility_name_length = APPOINTMENT_NAME_MAX_LENGTH - @appointment_date_time.length - 1
      "#{@facility_name.first(facility_name_length)} #{@appointment_date_time}"
    end
  end
end
