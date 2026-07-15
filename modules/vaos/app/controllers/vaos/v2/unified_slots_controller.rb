# frozen_string_literal: true

require 'common/exceptions'

module VAOS
  module V2
    class UnifiedSlotsController < VAOS::BaseController
      before_action :authorize_with_facilities

      STATSD_KEY_PREFIX = 'api.vaos.unified_slots'

      VALID_PROVIDER_TYPES = %w[va eps].freeze

      def index
        StatsD.measure("#{STATSD_KEY_PREFIX}.index.duration", tags: ["provider_type:#{provider_type_for_metrics}"]) do
          validate_provider_type!
          referral = fetch_referral
          provider = build_provider
          draft_id = maybe_create_draft(referral)
          slots = fetch_slots(provider, referral, draft_id)

          log_index_success(slots)
          render json: serialize_response(provider, slots, draft_id), status: :ok
        end
      rescue => e
        log_index_failure(e)
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
          params.permit(:clinic_id, :location_id, :clinical_service, :facility_type)
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
        when 'eps'
          build_eps_provider
        end
      end

      ##
      # +facility_type+ is forwarded from the FE (from the unified provider search response) so
      # {Unified::SlotsService} can detect Cerner vs VistA and decide whether to forward
      # +clinical_service+ to VPG. When omitted, the provider falls through as non-Cerner and
      # +clinical_service+ is dropped before the upstream call.
      def build_va_provider
        provider_params = va_provider_params
        ensure_pilot_station_allowed!(provider_params[:location_id])
        Unified::VAProvider.new(
          id: provider_params[:clinic_id],
          location_id: provider_params[:location_id],
          service_type: provider_params[:clinical_service],
          facility_type: provider_params[:facility_type]
        )
      end

      # Defense-in-depth for the pilot station allowlist. The provider search already
      # filters non-pilot stations out of the FE-visible list, but a stale FE cache or
      # a hand-crafted request could still target a non-pilot station -- reject those
      # with a 404 so they don't reach upstream VAOS.
      def ensure_pilot_station_allowed!(location_id)
        return if Unified::ParentStationFilter.allowed?(location_id)

        raise Common::Exceptions::RecordNotFound, location_id
      end

      def build_eps_provider
        provider_params = cc_provider_params
        Unified::EpsProvider.new(
          id: provider_params[:provider_service_id],
          network_id: provider_params[:network_id],
          appointment_types: [{ id: provider_params[:appointment_type_id], is_self_schedulable: true }]
        )
      end

      # Verify the referral isn't already used and mint a resumable Wellhive
      # draft. Both behaviors are encapsulated in
      # {VAOS::V2::Unified::EpsDraftService}; the controller stays out of
      # business logic and Redis concerns.
      def maybe_create_draft(referral)
        return nil unless provider_type == 'eps'

        draft_id = eps_draft_service.create_for_referral(referral)
        StatsD.increment("#{STATSD_KEY_PREFIX}.draft_created", tags: ['provider_type:eps'])
        draft_id
      end

      def fetch_slots(provider, referral, draft_id)
        start_dt = referral_start_date(referral)
        end_dt = Date.parse(referral.expiration_date).to_time(:utc).iso8601

        slots_service.slots_for(
          provider:,
          start_dt:,
          end_dt:,
          clinical_service: va_clinical_service_for(provider),
          appointment_id: draft_id
        )
      end

      # Reads the +clinical_service+ value back off the +Unified::VAProvider+
      # that {#build_va_provider} just constructed. EPS providers don't carry
      # a +service_type+ and the EPS slot path doesn't use +clinical_service+,
      # so return nil for them.
      def va_clinical_service_for(provider)
        return nil unless provider.is_a?(Unified::VAProvider)

        provider.service_type
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

      def eps_draft_service
        @eps_draft_service ||= Unified::EpsDraftService.new(current_user)
      end

      def log_index_success(slots)
        tags = ["provider_type:#{provider_type}"]
        StatsD.increment("#{STATSD_KEY_PREFIX}.index.success", tags:)
        StatsD.increment("#{STATSD_KEY_PREFIX}.index.no_results", tags:) if slots.blank?
      end

      def log_index_failure(error)
        Rails.logger.error(
          "#{STATSD_KEY_PREFIX}.index.failure",
          {
            error_class: error.class.name,
            provider_type: provider_type_safe,
            user_uuid: current_user&.uuid
          }
        )
        StatsD.increment(
          "#{STATSD_KEY_PREFIX}.index.failure",
          tags: [
            "provider_type:#{provider_type_safe}",
            "error_type:#{error.class.name.demodulize.underscore}"
          ]
        )
      end

      def provider_type_safe
        normalize_provider_type_tag(@provider_type || params[:provider_type])
      end

      def provider_type_for_metrics
        normalize_provider_type_tag(params[:provider_type])
      end

      def normalize_provider_type_tag(value)
        normalized = value.to_s.presence
        VALID_PROVIDER_TYPES.include?(normalized) ? normalized : 'unknown'
      end
    end
  end
end
