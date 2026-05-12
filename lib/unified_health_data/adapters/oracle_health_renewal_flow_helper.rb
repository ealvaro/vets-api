# frozen_string_literal: true

require 'mhv/oh_facilities_helper/service'

module UnifiedHealthData
  module Adapters
    # Determines whether the secure-message renewal flow is enabled for a given
    # Oracle Health prescription's facility.
    #
    # Uses a three-tier model:
    #   - Unknown facility (blank station): returns false (fail-safe)
    #   - Allowed facilities: always returns true
    #   - Rollout facilities: gated by Flipper percentage rollout per user
    #   - Default (unlisted): always returns false (blocked)
    # Allowed takes priority over rollout if a facility appears in both lists.
    #
    # @note Designed to be included in OracleHealthPrescriptionAdapter.
    module OracleHealthRenewalFlowHelper
      STATSD_PREFIX = 'unified_health_data.prescription.renewal_flow'

      # Determines whether the renewal messaging flow is enabled for a given prescription.
      # Returns false immediately if the prescription is not renewable, since non-renewable
      # prescriptions never expose the renewal messaging flow regardless of facility.
      #
      # @param is_renewable [Boolean] whether the prescription is renewable
      # @param station [String, nil] 3-digit station number
      # @param current_user [User] current user (Flipper actor for rollout gating)
      # @return [Boolean] true if the renewal flow is enabled for this prescription
      def compute_renewal_flow_enabled(is_renewable, station, current_user)
        return false unless is_renewable
        return false if station.blank?

        station_tag = "station:#{station}"

        if renewal_flow_allowed_facilities.include?(station)
          StatsD.increment("#{STATSD_PREFIX}.enabled", tags: [station_tag])
          return true
        end

        if renewal_flow_rollout_facilities.include?(station)
          enabled = Flipper.enabled?(:mhv_medications_oh_renewal_message_rollout, current_user)
          StatsD.increment("#{STATSD_PREFIX}.rollout", tags: [station_tag, "enabled:#{enabled}"])
          return enabled
        end

        StatsD.increment("#{STATSD_PREFIX}.blocked", tags: [station_tag])
        false
      end

      private

      def renewal_flow_allowed_facilities
        @renewal_flow_allowed_facilities ||=
          MHV::OhFacilitiesHelper::Service.parse_facility_setting(
            Settings.mhv.oh_facility_checks.renewal_flow_allowed_oh_facilities
          )
      end

      def renewal_flow_rollout_facilities
        @renewal_flow_rollout_facilities ||=
          MHV::OhFacilitiesHelper::Service.parse_facility_setting(
            Settings.mhv.oh_facility_checks.renewal_flow_rollout_oh_facilities
          )
      end
    end
  end
end
