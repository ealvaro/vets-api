# frozen_string_literal: true

require 'common/exceptions'

module VAOS
  module V2
    class UnifiedBookingsController < VAOS::BaseController
      before_action :authorize_with_facilities

      STATSD_KEY_PREFIX = 'api.vaos.unified_booking'

      VALID_PROVIDER_TYPES = %w[va community_care].freeze

      def create
        validate_provider_type!

        provider = build_provider
        slot = build_slot
        booking_service = resolve_booking_service

        confirmation = booking_service.book(
          user: current_user,
          provider:,
          slot:,
          params: booking_params
        )

        render json: serialize_confirmation(confirmation), status: :created
      rescue VAOS::V2::Unified::BookingArgumentError => e
        raise Common::Exceptions::ParameterMissing, e.message
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
        when 'community_care'
          build_eps_provider
        end
      end

      def build_va_provider
        Unified::VAProvider.new(
          id: params.require(:clinic_id),
          location_id: params.require(:location_id),
          service_type: params.require(:service_type)
        )
      end

      def build_eps_provider
        Unified::EpsProvider.new(
          id: params.require(:provider_service_id),
          provider_service_id: params[:provider_service_id],
          network_id: params.require(:network_id)
        )
      end

      def build_slot
        case provider_type
        when 'va'
          Unified::VASlot.new(id: params.require(:slot_id))
        when 'community_care'
          Unified::EpsSlot.new(
            id: params.require(:slot_id),
            provider_service_id: params[:provider_service_id]
          )
        end
      end

      def resolve_booking_service
        case provider_type
        when 'va'
          Unified::VABookingService.new
        when 'community_care'
          Unified::EpsBookingService.new
        end
      end

      def booking_params
        @booking_params ||= params.permit(
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

      def provider_type_safe
        @provider_type || 'unknown'
      end
    end
  end
end
