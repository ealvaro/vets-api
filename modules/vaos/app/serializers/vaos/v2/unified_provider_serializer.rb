# frozen_string_literal: true

module VAOS
  module V2
    class UnifiedProviderSerializer
      def serialize(providers, referral_npi: nil)
        providers.map.with_index do |provider, index|
          {
            id: provider.id,
            type: 'unified_provider',
            attributes: {
              name: provider.name,
              facilityName: provider.facility_name,
              providerType: provider.provider_type,
              isReferralProvider: referral_provider?(provider, referral_npi),
              address: serialize_address(provider.address),
              phone: provider.phone,
              latitude: provider.latitude,
              longitude: provider.longitude,
              distanceInMiles: provider.distance_from_user&.round(1),
              sortOrder: index
            }
          }
        end
      end

      private

      def referral_provider?(provider, referral_npi)
        return false if referral_npi.blank?
        return false unless provider.respond_to?(:npi)

        provider.npi == referral_npi
      end

      def serialize_address(address)
        return nil if address.blank?

        {
          street1: address[:street1],
          street2: address[:street2],
          street3: address[:street3],
          city: address[:city],
          state: address[:state],
          zip: address[:zip]
        }
      end
    end
  end
end
