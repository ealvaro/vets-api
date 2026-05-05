# frozen_string_literal: true

module VAOS
  module V2
    class UnifiedProviderSerializer
      def serialize(providers, referral_npi: nil)
        providers.map.with_index do |provider, index|
          attrs = {
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
          }.merge(type_specific_attributes(provider))

          { id: provider.id, type: 'unified_provider', attributes: attrs }
        end
      end

      private

      def type_specific_attributes(provider)
        case provider
        when Unified::VAProvider
          # +facilityType+ is round-tripped to the FE so it can be echoed back on the slots
          # request; {Unified::SlotsService} uses it (via {Unified::VAProvider#cerner?}) to gate
          # whether +clinicalService+ is forwarded to VPG (Cerner only; VistA rejects it).
          {
            locationId: provider.location_id,
            serviceType: provider.service_type,
            facilityType: provider.facility_type
          }.compact
        when Unified::EpsProvider
          {
            providerServiceId: provider.provider_service_id,
            networkId: provider.network_id,
            appointmentTypes: provider.appointment_types
          }.compact
        else
          {}
        end
      end

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
