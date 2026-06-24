# frozen_string_literal: true

module VAOS
  module V2
    class ProvidersController < VAOS::BaseController
      # GET /vaos/v2/providers
      # Returns a unified list of VA and CC providers near the user's address,
      # filtered by the referral's category of care. The referral's matched
      # provider is pinned to the top of the list.
      def index
        referral = fetch_referral
        providers = unified_search_service.search(
          referral:,
          radius: radius_param
        )

        serialized = unified_serializer.serialize(
          providers,
          referral_npi: referral.provider_npi
        )

        render json: { data: serialized }
      end

      private

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

      def unified_search_service
        @unified_search_service ||= VAOS::V2::Unified::ProviderSearchService.new(current_user)
      end

      def unified_serializer
        @unified_serializer ||= VAOS::V2::UnifiedProviderSerializer.new
      end
    end
  end
end
