# frozen_string_literal: true

require 'common/exceptions'
require 'unique_user_events'

module VAOS
  module V2
    class AppointmentsController < VAOS::BaseController
      before_action :authorize_with_facilities

      include VAOS::FacilityConstants

      # Local constants for this controller
      PARTIAL_RESPONSE_METRIC = 'api.vaos.va_mobile.response.partial'
      PAP_COMPLIANCE_TELE = 'PAP COMPLIANCE/TELE'
      APPT_INDEX_VAOS = "GET '/vaos/v1/patients/<icn>/appointments'"
      APPT_INDEX_VPG = "GET '/vpg/v1/patients/<icn>/appointments'"
      APPT_SHOW_VAOS = "GET '/vaos/v1/patients/<icn>/appointments/<id>'"
      APPT_SHOW_VPG = "GET '/vpg/v1/patients/<icn>/appointments/<id>'"
      APPT_CREATE_VAOS = "POST '/vaos/v1/patients/<icn>/appointments'"
      APPT_CREATE_VPG = "POST '/vpg/v1/patients/<icn>/appointments'"
      REASON = 'reason'
      REASON_CODE = 'reason_code'
      COMMENT = 'comment'

      def index
        appointments[:data].each do |appt|
          set_facility_error_msg(appt) if include_index_params[:facilities]
          scrape_appt_comments_and_log_details(appt, index_method_logging_name, PAP_COMPLIANCE_TELE)
          log_appt_creation_time(appt)
        end

        serializer = VAOS::V2::VAOSSerializer.new
        serialized = serializer.serialize(appointments[:data], 'appointments')

        # Log unique user event for appointments accessed (with facility tracking for OH events)
        UniqueUserEvents.log_event(
          user: current_user,
          event_name: UniqueUserEvents::EventRegistry::APPOINTMENTS_ACCESSED,
          event_facility_ids: appointment_facility_ids(appointments[:data])
        )

        if appointments[:meta][:failures] && appointments[:meta][:failures].empty?
          render json: { data: serialized, meta: appointments[:meta] }, status: :ok
        else
          StatsDMetric.new(key: PARTIAL_RESPONSE_METRIC).save
          StatsD.increment(PARTIAL_RESPONSE_METRIC, tags: ["failures:#{appointments[:meta][:failures]}"])
          render json: { data: serialized, meta: appointments[:meta] }, status: :multi_status
        end
      end

      def show
        appointment = appointment_show_params[:_include] == 'eps' ? eps_appointment : vaos_appointment

        set_facility_error_msg(appointment)

        scrape_appt_comments_and_log_details(appointment, show_method_logging_name, PAP_COMPLIANCE_TELE)
        log_appt_creation_time(appointment)

        serializer = VAOS::V2::VAOSSerializer.new
        serialized = serializer.serialize(appointment, 'appointments')
        render json: { data: serialized }
      end

      def create
        new_appointment
        set_facility_error_msg(new_appointment)

        scrape_appt_comments_and_log_details(new_appointment, create_method_logging_name, PAP_COMPLIANCE_TELE)

        serializer = VAOS::V2::VAOSSerializer.new
        serialized = serializer.serialize(new_appointment, 'appointments')
        render json: { data: serialized }, status: :created
      end

      def update
        updated_appointment
        set_facility_error_msg(updated_appointment)

        serializer = VAOS::V2::VAOSSerializer.new
        serialized = serializer.serialize(updated_appointment, 'appointments')
        render json: { data: serialized }
      end

      def get_avs_binaries
        render json: VAOS::V2::AvsBinarySerializer.new(avs_binaries), status: :ok
      end

      private

      # Extract unique facility IDs (3-character) from user-visible appointments for OH event tracking
      # Only includes appointments that are future, past, or pending (shown to users in the UI)
      # Note: location_id may be a sta6aid (5-6 characters like "983GC") - we extract only the
      # 3-character facility ID prefix to match against TRACKED_FACILITY_IDS
      # Returns nil if mhv_oh_unique_user_metrics_logging_appt feature flag is disabled
      # @param appointments [Array] list of appointment hashes/objects
      # @return [Array<String>, nil] unique 3-character facility IDs or nil if none/disabled
      def appointment_facility_ids(appointments)
        return nil unless Flipper.enabled?(:mhv_oh_unique_user_metrics_logging_appt)

        visible_appointments = appointments.select do |appt|
          # Pending appointments are always visible; non-cancelled appointments with date flags are visible
          appt[:pending] || (appt[:status] != 'cancelled' && (appt[:future] || appt[:past]))
        end
        station_ids = visible_appointments.filter_map { |appt| appt[:location_id]&.[](0..2) }.uniq
        station_ids.presence
      end

      def set_facility_error_msg(appointment)
        appointment[:location] = FACILITY_ERROR_MSG if appointment[:location_id].present? && appointment[:location].nil?
      end

      def appointments_service
        @appointments_service ||=
          VAOS::V2::AppointmentsService.new(current_user)
      end

      def mobile_facility_service
        @mobile_facility_service ||=
          VAOS::V2::MobileFacilityService.new(current_user)
      end

      def eps_appointment_service
        @eps_appointment_service ||=
          Eps::AppointmentService.new(current_user)
      end

      def eps_provider_service
        @eps_provider_service ||=
          Eps::ProviderService.new(current_user)
      end

      def appointments
        @appointments ||=
          appointments_service.get_appointments(start_date, end_date, statuses, pagination_params, include_index_params)
      end

      def vaos_appointment
        @appointment ||=
          appointments_service.get_appointment(appointment_id, include_show_params)
      end

      def eps_appointment
        @eps_appointment ||=
          eps_appointment_service.get_appointment(appointment_id:, retrieve_latest_details: true)
      end

      def new_appointment
        @new_appointment ||= get_new_appointment
      end

      def updated_appointment
        @updated_appointment ||=
          appointments_service.update_appointment(
            update_appt_id,
            status_update,
            kind: cancel_params[:kind],
            system_type: cancel_params[:system_type],
            service_type: cancel_params[:service_type],
            facility_id: cancel_params[:facility_id],
            type: cancel_params[:type]
          )
      end

      def avs_binaries
        @avs_binaries ||=
          appointments_service.fetch_avs_binaries(avs_binaries_params[:appointment_id],
                                                  avs_binaries_params[:doc_ids].split(','))
      end

      # Makes a call to the VAOS service to create a new appointment.
      def get_new_appointment
        appointments_service.post_appointment(create_params)
      end

      def scrape_appt_comments_and_log_details(appt, appt_method, comment_key)
        if appt&.[](:reason)&.include? comment_key
          log_appt_comment_data(appt, appt_method, appt&.[](:reason), comment_key, REASON)
        elsif appt&.[](:comment)&.include? comment_key
          log_appt_comment_data(appt, appt_method, appt&.[](:comment), comment_key, COMMENT)
        elsif appt&.[](:reason_code)&.[](:text)&.include? comment_key
          log_appt_comment_data(appt, appt_method, appt&.[](:reason_code)&.[](:text), comment_key, REASON_CODE)
        end
      end

      def log_appt_comment_data(appt, appt_method, comment_content, comment_key, field_name)
        appt_comment_data_entry = { "#{comment_key} appointment details" => appt_comment_log_details(appt, appt_method,
                                                                                                     comment_content,
                                                                                                     field_name) }
        Rails.logger.info("Details for #{comment_key} appointment", appt_comment_data_entry.to_json)
      end

      def log_appt_creation_time(appt)
        if appt.nil? || appt[:created].nil?
          Rails.logger.info('VAOS::V2::AppointmentsController appointment creation time: unknown')
        else
          creation_time = appt[:created]
          Rails.logger.info("VAOS::V2::AppointmentsController appointment creation time: #{creation_time}",
                            { created: creation_time }.to_json)
        end
      end

      def appt_comment_log_details(appt, appt_method, comment_content, field_name)
        {
          endpoint_method: appt_method,
          appointment_id: appt[:id],
          appointment_status: appt[:status],
          location_id: appt[:location_id],
          clinic: appt[:clinic],
          field_name:,
          comment: comment_content
        }
      end

      def update_appt_id
        params.require(:id)
      end

      def status_update
        params.require(:status)
      end

      def cancel_params
        params.permit(:kind, :system_type, :service_type, :facility_id, :type)
      end

      def appointment_index_params
        params.require(:start)
        params.require(:end)
        params.permit(:start, :end, :_include)
      end

      def appointment_show_params
        params.permit(:_include)
      end

      def avs_binaries_params
        params.require(:appointment_id)
        params.require(:doc_ids)
        params.permit(:appointment_id, :doc_ids)
      end

      # rubocop:disable Metrics/MethodLength
      def create_params
        @create_params ||= begin
          # Gets around a bug that turns param values of [] into [""]. This changes them back to [].
          # Without this the VAOS Service POST appointments call will fail as VAOS Service tries to parse [""].
          params.transform_values! { |v| v.is_a?(Array) && v.count == 1 && (v[0] == '') ? [] : v }

          params.permit(
            :kind,
            :status,
            :location_id,
            :system_type,
            :cancellable,
            :clinic,
            :comment,
            :reason,
            :service_type,
            :preferred_language,
            :minutes_duration,
            :patient_instruction,
            :priority,
            reason_code: [
              :text, { coding: %i[system code display] }
            ],
            slot: %i[id start end],
            contact: [{ telecom: %i[type value] }],
            practitioner_ids: %i[system value],
            requested_periods: %i[start end],
            practitioners: [
              :first_name,
              :last_name,
              :practice_name,
              {
                name: %i[family given]
              },
              {
                identifier: %i[system value]
              },
              {
                address: [
                  :type,
                  { line: [] },
                  :city,
                  :state,
                  :postal_code,
                  :country,
                  :text
                ]
              }
            ],
            preferred_location: %i[city state],
            preferred_times_for_phone_call: [],
            telehealth: [
              :url,
              :group,
              :vvs_kind,
              {
                atlas: [
                  :site_code,
                  :confirmation_code,
                  {
                    address: %i[
                      street_address city state
                      zip country latitude longitude
                      additional_details
                    ]
                  }
                ]
              }
            ],
            extension: %i[desired_date]
          )
        end
      end
      # rubocop:enable Metrics/MethodLength

      def start_date
        DateTime.parse(appointment_index_params[:start]).in_time_zone
      rescue ArgumentError
        raise Common::Exceptions::InvalidFieldValue.new('start', params[:start])
      end

      def end_date
        DateTime.parse(appointment_index_params[:end]).in_time_zone
      rescue ArgumentError
        raise Common::Exceptions::InvalidFieldValue.new('end', params[:end])
      end

      def include_index_params
        included = appointment_index_params[:_include]&.split(',')
        {
          clinics: ActiveModel::Type::Boolean.new.deserialize(included&.include?('clinics')),
          facilities: ActiveModel::Type::Boolean.new.deserialize(included&.include?('facilities')),
          avs: ActiveModel::Type::Boolean.new.deserialize(included&.include?('avs')),
          travel_pay_claims: ActiveModel::Type::Boolean.new.deserialize(included&.include?('travel_pay_claims')),
          eps: ActiveModel::Type::Boolean.new.deserialize(included&.include?('eps'))
        }
      end

      def include_show_params
        included = appointment_show_params[:_include]&.split(',')
        {
          avs: ActiveModel::Type::Boolean.new.deserialize(included&.include?('avs')),
          travel_pay_claims: ActiveModel::Type::Boolean.new.deserialize(included&.include?('travel_pay_claims'))
        }
      end

      def statuses
        s = params[:statuses]
        s.is_a?(Array) ? s.to_csv(row_sep: nil) : s
      end

      def appointment_id
        params[:appointment_id]
      end

      def index_method_logging_name
        if Flipper.enabled?(:va_online_scheduling_use_vpg)
          APPT_INDEX_VPG
        else
          APPT_INDEX_VAOS
        end
      end

      def show_method_logging_name
        if Flipper.enabled?(:va_online_scheduling_use_vpg)
          APPT_SHOW_VPG
        else
          APPT_SHOW_VAOS
        end
      end

      def create_method_logging_name
        if Flipper.enabled?(:va_online_scheduling_use_vpg)
          APPT_CREATE_VPG
        else
          APPT_CREATE_VAOS
        end
      end
    end
  end
end
