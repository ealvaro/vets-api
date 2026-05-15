# frozen_string_literal: true

module CheckIn
  module V2
    class AppointmentsController < CheckIn::ApplicationController
      before_action :before_logger, only: %i[index]
      after_action :after_logger, only: %i[index]

      def index
        check_in_session

        unless check_in_session.authorized?
          render json: check_in_session.unauthorized_message, status: :unauthorized and return
        end

        appointments

        merge_facilities_and_clinic(appointments[:data])
        serializer = VAOS::AppointmentSerializer.new(appt_struct_data)

        render json: serializer.serializable_hash.to_json, status: :ok
      end

      def permitted_params
        params.permit(:start, :end, :_include)
      end

      private

      def appt_struct_data
        struct = JSON.parse(appointments.to_json, object_class: OpenStruct)
        struct.data
      end

      def merge_facilities_and_clinic(appointments)
        appointments.each do |appt|
          next if appt[:locationId].blank?

          appt[:facility] = facility_service.get_facility_with_cache(facility_id: appt[:locationId])

          if appt[:clinic].present?
            appt[:clinicInfo] =
              facility_service.get_clinic_with_cache(facility_id: appt[:locationId], clinic_id: appt[:clinic])
          end
        end

        track_clinic_key_observability(appointments) if clinic_key_observability_enabled?
      end

      def clinic_key_observability_enabled?
        Flipper.enabled?(:check_in_experience_appointments_clinic_observability_enabled)
      end

      def track_clinic_key_observability(appointments)
        with_location = appointments.select { |appt| appt[:locationId].present? }
        total = with_location.size
        present = with_location.count { |appt| appt[:clinic].present? }
        missing_or_empty = total - present

        StatsD.increment(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_OBSERVABILITY_TOTAL, total)
        StatsD.increment(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_PRESENT, present)
        StatsD.increment(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_MISSING_OR_EMPTY, missing_or_empty)

        logger.info('HCE-Check-In') do
          "appointments_clinic_key_observability with_location_total=#{total} clinic_present=#{present} " \
            "clinic_missing_or_empty=#{missing_or_empty}"
        end
      end

      def check_in_session
        @check_in_session ||= CheckIn::V2::Session.build(data: { uuid: params[:session_id] }, jwt: low_auth_token)
      end

      def appointments
        @appointments ||= appointments_service.get_appointments(start_date, end_date)
      end

      def appointments_service
        @appointments_service ||= CheckIn::VAOS::AppointmentService.new(check_in_session:)
      end

      def facility_service
        @facility_service ||= CheckIn::VAOS::FacilityService.new
      end

      def start_date
        DateTime.parse(permitted_params[:start]).in_time_zone
      rescue ArgumentError
        raise Common::Exceptions::InvalidFieldValue.new('start', params[:start])
      end

      def end_date
        DateTime.parse(permitted_params[:end]).in_time_zone
      rescue ArgumentError
        raise Common::Exceptions::InvalidFieldValue.new('end', params[:end])
      end

      def authorize
        routing_error unless Flipper.enabled?(:check_in_experience_upcoming_appointments_enabled)
      end
    end
  end
end
