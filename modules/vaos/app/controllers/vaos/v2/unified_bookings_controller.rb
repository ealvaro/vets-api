# frozen_string_literal: true

require 'common/exceptions'

module VAOS
  module V2
    class UnifiedBookingsController < VAOS::BaseController
      before_action :authorize_with_facilities
      before_action :tag_provider_type_span

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
        confirmation = perform_booking
        render json: serialize_confirmation(confirmation), status: :created
      rescue VAOS::V2::Unified::BookingArgumentError => e
        # Surface the booking service's specific message (e.g. "referral_number or
        # referral_id is required for EPS booking") so the client gets an actionable
        # 400 instead of a generic parameter-missing complaint about an internal
        # variable name. Maps to Common::Exceptions::ParameterMissing (HTTP 400).
        raise Common::Exceptions::ParameterMissing.new('booking_params', detail: e.message)
      rescue Common::Exceptions::BaseError => e
        log_booking_failure(e) unless booking_error_already_logged?(e)
        raise
      rescue => e
        log_error(e) unless booking_error_already_logged?(e)
        log_booking_failure(e) unless booking_error_already_logged?(e)
        raise
      end

      private

      def perform_booking
        resolve_booking_service.book(
          user: current_user,
          provider: build_provider,
          slot: build_slot,
          params: create_booking_params
        )
      end

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
          permitted = params.permit(:clinic_id, :location_id, :service_type, :slot_id, :slot_start, :slot_end)
          permitted.require(:clinic_id)
          permitted.require(:location_id)
          permitted.require(:service_type)
          permitted.require(:slot_id)
          permitted
        end
      end

      def eps_unified_booking_params
        @eps_unified_booking_params ||= begin
          permitted = params.permit(:provider_service_id, :network_id, :slot_id, :slot_start, :slot_end)
          permitted.require(:provider_service_id)
          permitted.require(:network_id)
          permitted.require(:slot_id)
          permitted
        end
      end

      def build_va_provider
        booking_params = va_unified_booking_params
        ensure_pilot_station_allowed!(booking_params[:location_id])
        Unified::VAProvider.new(
          id: booking_params[:clinic_id],
          location_id: booking_params[:location_id],
          service_type: booking_params[:service_type]
        )
      end

      # Defense-in-depth for the pilot station allowlist. The provider search and slots
      # endpoints already filter non-pilot stations out, but a stale FE cache or a
      # hand-crafted booking request could still target a non-pilot station -- reject
      # those with a 404 before any upstream VAOS call is made.
      def ensure_pilot_station_allowed!(location_id)
        return if Unified::ParentStationFilter.allowed?(location_id)

        raise Common::Exceptions::RecordNotFound, location_id
      end

      def build_eps_provider
        booking_params = eps_unified_booking_params
        Unified::EpsProvider.new(
          id: booking_params[:provider_service_id],
          network_id: booking_params[:network_id]
        )
      end

      ##
      # +slot_start+ / +slot_end+ are forwarded so the booking services can populate downstream
      # fields the FE-supplied +slot_id+ alone can't reach: VA uses +slot.start+ to set
      # +extension.desired_date+ on the VAOS +post_appointment+ body, and EPS falls back to
      # +slot.start+ when the upstream draft response omits it (the appointments list filters
      # out EPS appointments missing a start time).
      def build_slot
        case provider_type
        when 'va'
          Unified::VASlot.new(
            id: va_unified_booking_params[:slot_id],
            start: va_unified_booking_params[:slot_start],
            end: va_unified_booking_params[:slot_end],
            location_id: va_unified_booking_params[:location_id]
          )
        when 'eps'
          Unified::EpsSlot.new(
            id: eps_unified_booking_params[:slot_id],
            start: eps_unified_booking_params[:slot_start],
            end: eps_unified_booking_params[:slot_end],
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

      # +appointment_id+ (Wellhive draft id) is intentionally NOT permitted.
      # The Wellhive draft id is a backend-managed implementation detail --
      # +VAOS::V2::UnifiedSlotsController#maybe_create_draft+ caches a draft id
      # under +(user_uuid, referral_number)+ and {VAOS::V2::Unified::EpsBookingService}
      # resolves it from the cache (or mints a fresh one on miss). Trusting a
      # client-supplied draft id led to a class of +400 invalid appointmentId+
      # failures when the FE populated this field with the +provider_service_id+
      # instead of the draft id from the slots response.
      def create_booking_params
        @create_booking_params ||= params.permit(
          :referral_number,
          :network_id,
          :provider_service_id,
          :slot_id,
          :comment,
          # +gender+ and +sex+ are both accepted: Wellhive's submit payload names this
          # field +sex+, while its +features.directBooking.requiredFields+ list calls the
          # same thing "gender". The FE sends +gender+, so both are permitted here and
          # normalized to the documented +sex+ in Eps::AppointmentService.
          additional_patient_attributes: [
            :phone, :email, :birth_date, :gender, :sex,
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

      def log_booking_failure(error)
        StatsD.increment(
          "#{STATSD_KEY_PREFIX}.failure",
          tags: [
            "provider_type:#{provider_type_safe}",
            "error_type:#{error.class.name.demodulize.underscore}"
          ]
        )
      end

      def booking_error_already_logged?(error)
        error.is_a?(VAOS::V2::Unified::BaseBookingService::AlreadyLogged)
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
        normalized = (@provider_type || params[:provider_type]).to_s.presence
        VALID_PROVIDER_TYPES.include?(normalized) ? normalized : 'unknown'
      end

      # Tags the request's root span with the provider type.
      #
      # Both actions on this controller serve VA direct scheduling and Community
      # Care through the same routes, so +resource_name+ alone cannot separate
      # them in APM. Without this tag, a VA-side error spike is indistinguishable
      # from a Community Care one on
      # +resource_name:vaos::v2::unifiedbookingscontroller_create+.
      #
      # Runs as a +before_action+ so it applies even when the action raises before
      # emitting any StatsD metric. Uses {#provider_type_safe} rather than
      # {#provider_type} so an invalid or missing +provider_type+ param tags as
      # +unknown+ instead of raising inside the callback.
      def tag_provider_type_span
        Datadog::Tracing.active_trace&.set_tag('provider_type', provider_type_safe)
      end
    end
  end
end
