# frozen_string_literal: true

require 'common/exceptions'

module VAOS
  module V2
    class UnifiedBookingsController < VAOS::BaseController
      before_action :authorize_with_facilities

      STATSD_KEY_PREFIX = 'api.vaos.unified_booking'
      include VAOS::FacilityConstants

      VALID_PROVIDER_TYPES = %w[va eps].freeze

      def show
        validate_provider_type!

        case provider_type
        when 'va'
          show_va_appointment
        when 'eps'
          show_eps_appointment
        end

        StatsD.increment("#{STATSD_KEY_PREFIX}.show.success", tags: ["provider_type:#{provider_type}"])
      rescue => e
        log_show_error(e)
        raise
      end

      def create
        validate_provider_type!

        provider = build_provider
        slot = build_slot
        booking_service = resolve_booking_service

        confirmation = booking_service.book(
          user: current_user,
          provider:,
          slot:,
          params: create_booking_params
        )

        render json: serialize_confirmation(confirmation), status: :created
      rescue VAOS::V2::Unified::BookingArgumentError
        raise Common::Exceptions::ParameterMissing, 'create_booking_params'
      rescue Common::Exceptions::BaseError
        raise
      rescue => e
        log_error(e) unless e.is_a?(VAOS::V2::Unified::BaseBookingService::AlreadyLogged)
        raise
      end

      private

      def provider_type
        @provider_type ||= params.require(:provider_type)
      end

      def validate_provider_type!
        return if VALID_PROVIDER_TYPES.include?(provider_type)

        raise Common::Exceptions::InvalidFieldValue.new('provider_type', provider_type)
      end

      def build_provider
        case provider_type
        when 'va'
          build_va_provider
        when 'eps'
          build_eps_provider
        end
      end

      def va_unified_booking_params
        @va_unified_booking_params ||= begin
          permitted = params.permit(:clinic_id, :location_id, :service_type, :slot_id)
          permitted.require(:clinic_id)
          permitted.require(:location_id)
          permitted.require(:service_type)
          permitted.require(:slot_id)
          permitted
        end
      end

      def eps_unified_booking_params
        @eps_unified_booking_params ||= begin
          permitted = params.permit(:provider_service_id, :network_id, :slot_id)
          permitted.require(:provider_service_id)
          permitted.require(:network_id)
          permitted.require(:slot_id)
          permitted
        end
      end

      def build_va_provider
        p = va_unified_booking_params
        Unified::VAProvider.new(
          id: p[:clinic_id],
          location_id: p[:location_id],
          service_type: p[:service_type]
        )
      end

      def build_eps_provider
        p = eps_unified_booking_params
        Unified::EpsProvider.new(
          id: p[:provider_service_id],
          network_id: p[:network_id]
        )
      end

      def build_slot
        case provider_type
        when 'va'
          Unified::VASlot.new(id: va_unified_booking_params[:slot_id])
        when 'eps'
          Unified::EpsSlot.new(
            id: eps_unified_booking_params[:slot_id],
            provider_service_id: eps_unified_booking_params[:provider_service_id]
          )
        end
      end

      def resolve_booking_service
        case provider_type
        when 'va'
          Unified::VABookingService.new
        when 'eps'
          Unified::EpsBookingService.new
        end
      end

      def create_booking_params
        @create_booking_params ||= params.permit(
          :referral_number,
          :network_id,
          :provider_service_id,
          :slot_id,
          :appointment_id,
          :comment,
          additional_patient_attributes: [
            :phone, :email, :birth_date, :gender,
            { name: [:family, { given: [] }] },
            { address: [:type, :city, :state, :country, :postal_code, { line: [] }] }
          ]
        ).to_h.deep_symbolize_keys
      end

      def serialize_confirmation(confirmation)
        {
          data: {
            id: confirmation[:appointment_id],
            type: 'unified_booking',
            attributes: {
              appointment_id: confirmation[:appointment_id],
              provider_type: confirmation[:provider_type],
              status: confirmation[:status],
              start: confirmation[:start]
            }.compact
          }
        }
      end

      def show_va_appointment
        appointment = vaos_appointments_service.get_appointment(params.require(:id), {})
        set_facility_error_msg(appointment)
        serializer = Unified::AppointmentSerializer.new(appointment, care_type: 'VA')
        render json: serializer.serialize
      end

      def show_eps_appointment
        appointment_data = eps_appointment_service.get_appointment(
          appointment_id: params.require(:id),
          retrieve_latest_details: true
        )

        provider = fetch_provider_safely(appointment_data)
        eps_appointment = VAOS::V2::EpsAppointment.new(appointment_data, provider)
        serializer = Unified::AppointmentSerializer.new(eps_appointment, care_type: 'CC')
        render json: serializer.serialize
      end

      def set_facility_error_msg(appointment)
        appointment[:location] = FACILITY_ERROR_MSG if appointment[:location_id].present? && appointment[:location].nil?
      end

      ##
      # Fetches provider details for an EPS appointment. Returns nil on failure so that
      # a transient provider-service outage doesn't break polling -- the appointment status
      # still reaches the frontend, just without provider details.
      def fetch_provider_safely(appointment_data)
        provider_id = appointment_data[:provider_service_id]
        return nil if provider_id.nil?

        eps_provider_service.get_provider_service(provider_id:)
      rescue => e
        Rails.logger.error(
          "#{STATSD_KEY_PREFIX}.provider_fetch_failed",
          {
            error_class: e.class.name,
            provider_type: 'eps',
            user_uuid: current_user&.uuid
          }
        )
        StatsD.increment("#{STATSD_KEY_PREFIX}.provider_fetch_failed", tags: ['provider_type:eps'])
        nil
      end

      def log_show_error(error)
        Rails.logger.error(
          "#{STATSD_KEY_PREFIX}.show_error",
          {
            error_class: error.class.name,
            provider_type: provider_type_safe,
            user_uuid: current_user&.uuid
          }
        )
        StatsD.increment(
          "#{STATSD_KEY_PREFIX}.show.failure",
          tags: ["provider_type:#{provider_type_safe}", "error_type:#{error.class.name.demodulize.underscore}"]
        )
      end

      def log_error(error)
        Rails.logger.error(
          "#{STATSD_KEY_PREFIX}.controller_error",
          {
            error_class: error.class.name,
            provider_type: provider_type_safe,
            user_uuid: current_user&.uuid
          }
        )
        StatsD.increment(
          "#{STATSD_KEY_PREFIX}.controller_error",
          tags: ["provider_type:#{provider_type_safe}", "error_type:#{error.class.name.demodulize.underscore}"]
        )
      end

      def vaos_appointments_service
        @vaos_appointments_service ||= VAOS::V2::AppointmentsService.new(current_user)
      end

      def eps_appointment_service
        @eps_appointment_service ||= Eps::AppointmentService.new(current_user)
      end

      def eps_provider_service
        @eps_provider_service ||= Eps::ProviderService.new(current_user)
      end

      def provider_type_safe
        @provider_type || 'unknown'
      end
    end
  end
end
