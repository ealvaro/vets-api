# frozen_string_literal: true

require 'common/exceptions'

module VAOS
  module V2
    class UnifiedSlotsController < VAOS::BaseController
      before_action :authorize_with_facilities

      STATSD_KEY_PREFIX = 'api.vaos.unified_slots'

      VALID_PROVIDER_TYPES = %w[va community_care].freeze

      def index
        validate_provider_type!
        referral = fetch_referral
        provider = build_provider
        draft_id = maybe_create_draft(referral)
        slots = fetch_slots(provider, referral, draft_id)

        render json: serialize_response(provider, slots, draft_id), status: :ok
      rescue Common::Exceptions::BaseError
        raise
      rescue => e
        log_error(e)
        raise
      end

      private

      def provider_type
        @provider_type ||= params.require(:provider_type)
      end

      def referral_id
        @referral_id ||= params.require(:referral_id)
      end

      def va_provider_params
        @va_provider_params ||= begin
          params.require(:clinic_id)
          params.require(:location_id)
          params.permit(:clinic_id, :location_id, :clinical_service)
        end
      end

      def cc_provider_params
        @cc_provider_params ||= begin
          params.require(:provider_service_id)
          params.require(:appointment_type_id)
          params.permit(:provider_service_id, :appointment_type_id, :network_id)
        end
      end

      def validate_provider_type!
        return if VALID_PROVIDER_TYPES.include?(provider_type)

        raise Common::Exceptions::InvalidFieldValue.new('provider_type', provider_type)
      end

      def fetch_referral
        decrypted_id = VAOS::ReferralEncryptionService.decrypt(referral_id)
        raise Common::Exceptions::InvalidFieldValue.new('referral_id', referral_id) if decrypted_id.blank?

        Ccra::ReferralService.new(current_user).get_referral(decrypted_id, current_user.icn)
      rescue VAOS::Exceptions::ConfigurationError
        raise Common::Exceptions::InvalidFieldValue.new('referral_id', referral_id)
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
        vp = va_provider_params
        Unified::VAProvider.new(
          id: vp[:clinic_id],
          location_id: vp[:location_id],
          service_type: vp[:clinical_service]
        )
      end

      def build_eps_provider
        cp = cc_provider_params
        Unified::EpsProvider.new(
          id: cp[:provider_service_id],
          provider_service_id: cp[:provider_service_id],
          network_id: cp[:network_id],
          appointment_types: [{ id: cp[:appointment_type_id], is_self_schedulable: true }]
        )
      end

      def maybe_create_draft(referral)
        return nil unless provider_type == 'community_care'

        draft = eps_appointment_service.create_draft_appointment(referral_id: referral.referral_number)

        if draft.id.blank?
          raise Common::Exceptions::BackendServiceException.new(
            'VAOS_502',
            detail: 'EPS draft response missing appointment id'
          )
        end

        StatsD.increment("#{STATSD_KEY_PREFIX}.draft_created")
        draft.id
      end

      def fetch_slots(provider, referral, draft_id)
        start_dt = referral_start_date(referral)
        end_dt = Date.parse(referral.expiration_date).to_time(:utc).iso8601

        slots_service.slots_for(
          provider:,
          start_dt:,
          end_dt:,
          clinical_service: params[:clinical_service],
          appointment_id: draft_id
        )
      end

      def referral_start_date(referral)
        [Date.parse(referral.referral_date), Date.current].max.to_time(:utc).iso8601
      end

      def serialize_response(provider, slots, draft_appointment_id)
        Unified::ProviderSlotsSerializer.new(
          provider:,
          slots:,
          draft_appointment_id:
        ).serialize
      end

      def slots_service
        @slots_service ||= Unified::SlotsService.new(current_user)
      end

      def eps_appointment_service
        @eps_appointment_service ||= Eps::AppointmentService.new(current_user)
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
