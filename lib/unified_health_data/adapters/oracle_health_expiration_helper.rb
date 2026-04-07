# frozen_string_literal: true

module UnifiedHealthData
  module Adapters
    # Extracts and normalizes Oracle Health prescription expiration dates.
    #
    # Oracle Health encodes expiration timestamps as 23:59:59 in the station's
    # local timezone, converted to UTC. This module infers the intended calendar
    # date and returns noon UTC, preventing off-by-one display errors in
    # western timezones.
    module OracleHealthExpirationHelper
      def extract_expiration_date(resource)
        raw_date = resource.dig('dispenseRequest', 'validityPeriod', 'end')
        return nil if raw_date.blank?

        # Primary: infer the local calendar date from the UTC timestamp.
        # OH always encodes expiration as 23:59:59 local → UTC, so subtracting
        # 12 hours recovers the correct date for all US offsets (UTC-11..UTC+10).
        inferred = infer_local_date_noon_utc(raw_date)
        return inferred if inferred.nil?

        # Cross-check: if we can look up the facility timezone, compare the two
        # results and log a warning if they disagree.
        verify_inferred_date_against_facility(raw_date, inferred, resource)

        inferred
      end

      # Compares the inferred expiration date with the facility-timezone-derived date.
      # Logs a warning if they disagree, which would indicate an unexpected UTC offset
      # or a non-standard timestamp format from Oracle Health.
      def verify_inferred_date_against_facility(raw_date, inferred, resource)
        station_number = extract_station_number(resource)
        return if station_number.blank? || !station_number.match?(/^\d{3}$/)

        timezone = facility_timezone_for(station_number)
        return if timezone.blank?

        facility_derived = normalize_date_to_noon_utc(raw_date, timezone)
        # If facility_derived is nil, normalize_date_to_noon_utc already logged the reason.
        return if facility_derived.nil? || facility_derived == inferred

        Rails.logger.warn(
          message: 'Expiration date mismatch between inferred and facility timezone',
          inferred_date: inferred, facility_date: facility_derived,
          raw_date:, station_number:, facility_timezone: timezone, service: 'unified_health_data'
        )
      end

      # Infers the local calendar date from an Oracle Health UTC timestamp and returns
      # noon UTC of that date. OH expiration timestamps are always 23:59:59 in the
      # station's local timezone. Subtracting 12 hours from the UTC representation
      # always lands on the same calendar date as the original local time, regardless
      # of the station's UTC offset (valid for UTC-11 through UTC+10).
      #
      # @param utc_date_string [String] ISO 8601 UTC date string (e.g., "2026-11-17T07:59:59Z")
      # @return [String, nil] ISO 8601 string at noon UTC, or nil if invalid
      def infer_local_date_noon_utc(utc_date_string)
        parsed = Time.zone.parse(utc_date_string)
        return log_unparseable_expiration(utc_date_string) unless parsed

        local_date = (parsed - 12.hours).utc.to_date
        Time.utc(local_date.year, local_date.month, local_date.day, 12, 0, 0).iso8601(3)
      rescue ArgumentError => e
        log_unparseable_expiration(utc_date_string, e.message)
      end

      def log_unparseable_expiration(raw_date, error = nil)
        Rails.logger.warn(
          message: 'Unable to parse OH expiration date',
          raw_date:, error:, service: 'unified_health_data'
        )
        nil
      end

      # Memoizes timezone lookups per station number within the adapter instance
      # to avoid redundant remote Redis/cache round-trips when multiple
      # prescriptions share the same station.
      def facility_timezone_for(station_number)
        @facility_timezone_cache ||= {}
        return @facility_timezone_cache[station_number] if @facility_timezone_cache.key?(station_number)

        @facility_timezone_cache[station_number] = facility_timezone_service.get_facility_timezone(station_number)
      end
    end
  end
end
