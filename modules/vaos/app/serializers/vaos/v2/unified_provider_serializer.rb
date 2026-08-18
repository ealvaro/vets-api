# frozen_string_literal: true

module VAOS
  module V2
    class UnifiedProviderSerializer
      # @param include_online_scheduling [Boolean] When true, adds the +onlineScheduling+ attribute
      #   indicating whether each provider can be scheduled online (vs. call-to-schedule only).
      #   Gated by the post-MVP flag so the key only appears once the enhancement is enabled.
      # @param ranked [Boolean] When true, adds the ranked-search attributes: +rationale+ (the
      #   human-readable explanation from {Unified::ProviderRanker}) and +recommended+ (true on the
      #   group's best-scoring provider, as marked by ProviderSearchService#search_grouped -- not
      #   necessarily the first row, since the referral's matched provider is pinned to the top of
      #   the EPS group regardless of score). Left off for the legacy flat-list path so that payload
      #   is unchanged; +matchScore+ is intentionally kept internal and not surfaced in phase 1.
      def serialize(providers, referral_npi: nil, include_online_scheduling: false, ranked: false)
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
            nextAvailableDate: provider.next_available_date,
            sortOrder: index
          }.merge(type_specific_attributes(provider))
                  .merge(drive_time_attributes(provider))

          attrs[:onlineScheduling] = provider.online_scheduling? if include_online_scheduling
          attrs.merge!(ranked_attributes(provider)) if ranked

          { id: provider.id, type: 'unified_provider', attributes: attrs }
        end
      end

      private

      # +recommended+ echoes the model marker set by ProviderSearchService#mark_recommended
      # (the group's best-scoring provider), NOT list position -- the pinned referral provider
      # sits first regardless of score. +matchScore+ is intentionally omitted: separate VA/EPS
      # ranking makes cross-group scores non-comparable, so phase 1 surfaces order + rationale only.
      def ranked_attributes(provider)
        { rationale: provider.rationale, recommended: provider.recommended == true }
      end

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

      def drive_time_attributes(provider)
        seconds = provider.drive_time_in_seconds
        return {} unless seconds&.positive?

        { driveTimeInSeconds: seconds, driveTime: format_drive_time(seconds) }
      end

      def format_drive_time(seconds)
        minutes = [(seconds / 60.0).round, 1].max
        return "#{minutes} minute drive" if minutes < 60

        hours, remainder = minutes.divmod(60)
        remainder.zero? ? "#{hours} hour drive" : "#{hours} hour and #{remainder} minute drive"
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
