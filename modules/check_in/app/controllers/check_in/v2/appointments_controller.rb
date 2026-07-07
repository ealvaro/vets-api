# frozen_string_literal: true

module CheckIn
  module V2
    class AppointmentsController < CheckIn::ApplicationController
      before_action :before_logger, only: %i[index]
      after_action :after_logger, only: %i[index]

      def index
        appointment_rows = nil
        check_in_session

        unless check_in_session.authorized?
          render json: check_in_session.unauthorized_message, status: :unauthorized and return
        end

        appointment_rows = appointments[:data]
        merge_facilities_and_clinic(appointment_rows)
        serializer = VAOS::AppointmentSerializer.new(appt_struct_data)

        render json: serializer.serializable_hash.to_json, status: :ok
      ensure
        track_clinic_observability(appointment_rows) if track_clinic_observability?(appointment_rows)
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
        facility_service.track_vds_clinics_skipped_flag_off!

        appointments.each do |appt|
          next if appt[:locationId].blank?

          appt[:facility] = facility_service.get_facility_with_cache(facility_id: appt[:locationId])

          if appt[:clinic].present?
            appt[:clinicInfo] =
              facility_service.get_clinic_with_cache(
                facility_id: appt[:locationId],
                clinic_id: appt[:clinic],
                facility: appt[:facility]
              )
          end
        end
      end

      def track_clinic_observability?(appointment_rows)
        clinic_observability_enabled? && !appointment_rows.nil?
      end

      def clinic_observability_enabled?
        Flipper.enabled?(:check_in_experience_appointments_clinic_observability_enabled)
      end

      def track_clinic_observability(appointments)
        counts = clinic_observability_counts(appointments)
        increment_clinic_observability_metrics(counts)

        logger.info('HCE-Check-In') do
          { event: 'appointments_clinic_observability', **counts }
        end
      end

      def clinic_observability_counts(appointments)
        with_location_total = 0
        clinic_key_present = 0
        clinic_enrichment_total = 0
        clinic_info_present = 0

        appointments.each do |appt|
          next if appt[:locationId].blank?

          with_location_total += 1
          next if appt[:clinic].blank?

          clinic_key_present += 1
          clinic_enrichment_total += 1
          clinic_info_present += 1 if appt.dig(:clinicInfo, :data, :serviceName).present?
        end

        {
          with_location_total:,
          clinic_key_present:,
          clinic_key_missing_or_empty: with_location_total - clinic_key_present,
          clinic_enrichment_total:,
          clinic_info_present:,
          clinic_info_missing: clinic_enrichment_total - clinic_info_present
        }
      end

      def increment_clinic_observability_metrics(counts)
        StatsD.increment(
          CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_OBSERVABILITY_TOTAL, counts[:with_location_total]
        )
        StatsD.increment(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_PRESENT, counts[:clinic_key_present])
        StatsD.increment(
          CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_MISSING_OR_EMPTY, counts[:clinic_key_missing_or_empty]
        )
        StatsD.increment(
          CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_TOTAL, counts[:clinic_enrichment_total]
        )
        StatsD.increment(
          CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_PRESENT, counts[:clinic_info_present]
        )
        StatsD.increment(
          CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_MISSING, counts[:clinic_info_missing]
        )
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
