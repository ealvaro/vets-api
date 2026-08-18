# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class BaseProvider
        attr_accessor :id, :name, :facility_name, :address, :phone, :latitude, :longitude,
                      :provider_type, :distance_from_user, :next_available_date,
                      :drive_time_in_seconds,
                      # Populated by {Unified::ProviderRanker}. +match_score+ (0-100) and
                      # +rationale+ drive ranked provider search; +recommended+ marks the group's
                      # best-scoring provider (which may not sit first -- the referral's matched
                      # provider is pinned to the top of the EPS group regardless of score);
                      # +seen_before+ is the phase-2 continuity signal (nil = unknown, not yet
                      # joined against appt history).
                      :match_score, :rationale, :recommended, :seen_before

        def initialize(attrs = {})
          attrs.each { |key, value| send(:"#{key}=", value) if respond_to?(:"#{key}=") }
        end

        ##
        # Whether this provider can be scheduled online (vs. call-to-schedule only).
        #
        # Defaults to +true+: VA providers only reach the unified provider list after passing a
        # +direct_eligible+ check, so they are always online-schedulable. EPS providers override
        # this to derive the value from their Wellhive digital-booking features.
        #
        # @return [Boolean]
        def online_scheduling?
          true
        end

        def formatted_address
          return nil if address.blank?

          parts = [
            address[:street1], address[:street2], address[:street3],
            address[:city], address[:state], address[:zip]
          ].compact
          parts.join(', ')
        end
      end
    end
  end
end
