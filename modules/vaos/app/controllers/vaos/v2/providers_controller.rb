# frozen_string_literal: true

module VAOS
  module V2
    class ProvidersController < VAOS::BaseController
      # GET /vaos/v2/providers
      # Returns VA and CC providers near the user's address, filtered by the referral's category of
      # care. The referral's matched provider is pinned to the top of the CC results.
      #
      # Response shape is gated by the +unified_appointments_internal_provider_ranker+ flag
      # (hard cutover):
      #   * flag OFF (legacy): +data+ is a single flat array, sorted by distance.
      #   * flag ON (ranked):  +data+ is +{ vaProviders: [...], epsProviders: [...] }+, each ranked
      #     separately by {Unified::ProviderRanker}.
      def index
        referral = fetch_referral

        if provider_ranker_enabled?
          render json: { data: ranked_provider_groups(referral) }
        else
          render json: { data: legacy_provider_list(referral) }
        end
      end

      private

      def ranked_provider_groups(referral)
        grouped = unified_search_service.search_grouped(referral:, radius: radius_param)

        {
          vaProviders: serialize_group(grouped[:va], referral),
          epsProviders: serialize_group(grouped[:eps], referral)
        }
      end

      def serialize_group(providers, referral)
        unified_serializer.serialize(
          providers,
          referral_npi: referral.provider_npi,
          include_online_scheduling: call_to_schedule_providers_enabled?,
          ranked: true
        )
      end

      def legacy_provider_list(referral)
        providers = unified_search_service.search(referral:, radius: radius_param)
        unified_serializer.serialize(
          providers,
          referral_npi: referral.provider_npi,
          include_online_scheduling: call_to_schedule_providers_enabled?
        )
      end

      def fetch_referral
        referral_id = params.require(:referral_id)
        raise Common::Exceptions::InvalidFieldValue.new('referral_id', referral_id) if referral_id.blank?

        decrypted_id = VAOS::ReferralEncryptionService.decrypt(referral_id)
        raise Common::Exceptions::InvalidFieldValue.new('referral_id', referral_id) if decrypted_id.blank?

        Ccra::ReferralService.new(current_user).get_referral(decrypted_id, current_user.icn)
      rescue VAOS::Exceptions::ConfigurationError
        raise Common::Exceptions::InvalidFieldValue.new('referral_id', referral_id)
      end

      def radius_param
        default_radius = VAOS::V2::Unified::ProviderSearchService.default_radius_miles
        raw_radius = params[:radius]
        return default_radius if raw_radius.nil?

        parsed_radius = Integer(raw_radius, 10)
        parsed_radius.positive? ? parsed_radius : default_radius
      rescue ArgumentError, TypeError
        default_radius
      end

      # Flag gating the call-to-schedule (non-online-scheduling) provider enhancements.
      def call_to_schedule_providers_enabled?
        Flipper.enabled?(:va_online_scheduling_cc_direct_scheduling_v2_post_mvp, current_user)
      end

      # Flag gating the deterministic ranked-provider response. Hard cutover: flips the response
      # shape from a flat array to separate +vaProviders+/+epsProviders+ groups (see #index).
      def provider_ranker_enabled?
        Flipper.enabled?(:unified_appointments_internal_provider_ranker, current_user)
      end

      def unified_search_service
        @unified_search_service ||= VAOS::V2::Unified::ProviderSearchService.new(current_user)
      end

      def unified_serializer
        @unified_serializer ||= VAOS::V2::UnifiedProviderSerializer.new
      end
    end
  end
end
