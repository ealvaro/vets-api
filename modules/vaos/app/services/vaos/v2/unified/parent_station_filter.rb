# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      ##
      # Pilot scope filter: limits the unified scheduling flow to a set of allowed
      # VA parent stations, configured via AWS Parameter Store / ECS env as a
      # comma-delimited list (+vaos__unified_scheduling__allowed_parent_stations+).
      #
      # Lighthouse and VAOS return station IDs that may include a non-digit suffix
      # identifying a satellite/CBOC under a parent VAMC (e.g. +"983GC"+ rolls up to
      # the +"983"+ parent). Only the leading-digit prefix is compared against the
      # allowlist so satellites and CBOCs are correctly attributed to their parent.
      #
      # When the allowlist is unset or blank, the filter is disabled and all stations
      # pass through. This is the default behavior for staging, dev, and test.
      #
      # @example AWS Parameter Store value
      #   "983, 442"        # spaces ignored
      #   "983,442"         # also fine
      #   ""  / unset       # filter disabled (allow everything)
      #
      # @example Usage
      #   ParentStationFilter.allowed?('983GC')   # => true if "983" is in the list
      #   ParentStationFilter.parent_id_for('442QA') # => "442"
      #
      module ParentStationFilter
        module_function

        ##
        # @return [Array<String>] the allowed parent station IDs, with whitespace
        #   stripped and blanks dropped. Empty array when the filter is disabled.
        def allowed_parents
          parse(Settings.vaos&.unified_scheduling&.allowed_parent_stations)
        end

        ##
        # @return [Boolean] true when an allowlist is configured (any non-blank
        #   entries). When false, {.allowed?} returns true for every input.
        def enabled?
          allowed_parents.any?
        end

        ##
        # @param station_id [String, Integer, nil] facility/clinic station ID, possibly
        #   including a satellite suffix (+"983GC"+) or +nil+.
        # @return [Boolean] true if the filter is disabled, OR the parent of
        #   +station_id+ is in the allowlist. False when the parent can't be derived
        #   (e.g. all-letter or blank input) under an active allowlist.
        def allowed?(station_id)
          return true unless enabled?

          parent = parent_id_for(station_id)
          parent.present? && allowed_parents.include?(parent)
        end

        ##
        # Extracts the leading-digit prefix from a station ID. Lighthouse uses this
        # convention for satellite/CBOC rollups (+"983GC"+ -> +"983"+).
        #
        # @return [String, nil] the parent station digits, or +nil+ when the input
        #   has no leading digits (purely-letter codes, blank, or +nil+).
        def parent_id_for(station_id)
          str = station_id.to_s
          match = str.match(/\A(\d+)/)
          match && match[1]
        end

        ##
        # @api private (exposed for tests)
        def parse(raw)
          return [] if raw.blank?

          raw.to_s.split(',').map(&:strip).compact_blank.uniq
        end
      end
    end
  end
end
