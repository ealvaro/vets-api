# frozen_string_literal: true

require 'medical_records/medical_records_log'

module UnifiedHealthData
  module Adapters
    # DateTime parsing and timezone conversion utilities for FHIR resources.
    # Extracted from FhirHelpers to provide focused date/time functionality.
    module DateTimeHelpers
      LABS = MedicalRecords::MedicalRecordsLog::LABS_AND_TESTS
      # Parses a date string or returns epoch if invalid/missing
      #
      # @param date_string [String, nil] Date string to parse
      # @return [Time] Parsed time or epoch
      def parse_date_or_epoch(date_string)
        return Time.zone.at(0) unless date_string

        parsed_time = Time.zone.parse(date_string)
        parsed_time || Time.zone.at(0)
      rescue ArgumentError, TypeError
        Time.zone.at(0)
      end

      # Converts a UTC datetime string to facility local time
      #
      # @param date_string [String] ISO 8601 datetime string (e.g., '2023-11-06T18:32:00+00:00')
      # @param timezone [String] IANA timezone ID (e.g., 'America/Los_Angeles')
      # @return [String] ISO 8601 datetime string in facility local time, or original if conversion fails
      def convert_to_facility_time(date_string, timezone)
        return date_string if date_string.blank? || timezone.blank?

        begin
          # Parse the datetime and convert to the facility timezone
          parsed_time = DateTime.parse(date_string).to_time.utc
          local_time = parsed_time.in_time_zone(timezone)
          local_time.iso8601
        rescue ArgumentError, TypeError, TZInfo::InvalidTimezoneIdentifier, TZInfo::UnknownTimezone => e
          log_timezone_conversion_error(e, date_string, timezone)
          date_string
        end
      end

      # Normalizes a date to noon UTC of the intended calendar date.
      # VistA encodes expiration as midnight Eastern (start of day) and Oracle Health
      # as 23:59:59 local→UTC — both can produce a UTC date that differs from the
      # intended local date. Noon UTC falls on the same calendar date in every US
      # timezone (UTC-11 Samoa through UTC+10 Guam), preventing off-by-one errors.
      #
      # @param date_string [String] ISO 8601 or RFC 2822 date string
      # @param timezone [String] IANA timezone for interpreting the date
      # @return [String, nil] "YYYY-MM-DDT12:00:00.000Z" or nil if invalid
      def normalize_date_to_noon_utc(date_string, timezone)
        return nil if date_string.blank? || timezone.blank?

        zone = Time.find_zone(timezone)
        return log_unknown_timezone(date_string, timezone) unless zone

        parsed = zone.parse(date_string)
        return nil unless parsed

        local_date = parsed.to_date
        Time.utc(local_date.year, local_date.month, local_date.day, 12, 0, 0).iso8601(3)
      rescue ArgumentError => e
        Rails.logger.warn("Failed to normalize date '#{date_string}' in timezone '#{timezone}': #{e.message}")
        nil
      end

      # Normalizes date values to a consistent ISO 8601 format for reliable sorting.
      # Handles various input formats and ensures consistent comparison behavior.
      #
      # @param date_value [String, nil] The date value to normalize
      # @return [String] Normalized ISO 8601 date string
      #
      # @example Year only
      #   normalize_date_for_sorting("2024") #=> "2024-01-01T00:00:00Z"
      # @example Date without time
      #   normalize_date_for_sorting("2024-11-08") #=> "2024-11-08T00:00:00Z"
      # @example Full datetime (passthrough)
      #   normalize_date_for_sorting("2024-11-08T10:00:00Z") #=> "2024-11-08T10:00:00Z"
      # @example Nil (sorts to end in descending order)
      #   normalize_date_for_sorting(nil) #=> "1900-01-01T00:00:00Z"
      def normalize_date_for_sorting(date_value)
        return '1900-01-01T00:00:00Z' if date_value.nil?
        return "#{date_value}-01-01T00:00:00Z" if date_value.match?(/^\d{4}$/)
        return "#{date_value}T00:00:00Z" if date_value.match?(/^\d{4}-\d{2}-\d{2}$/)

        date_value
      end

      private

      # @api private
      def log_unknown_timezone(date_string, timezone)
        Rails.logger.warn("Unknown timezone '#{timezone}' when normalizing date '#{date_string}'")
        nil
      end

      # Log resource identifier used when attributing timezone conversion errors.
      # Defaults to LABS for backward compatibility; including adapters should
      # override this to attribute errors to their own domain (e.g., CONDITIONS).
      #
      # @api private
      def timezone_conversion_log_resource
        LABS
      end

      # @api private
      def log_timezone_conversion_error(error, date_string, timezone)
        log_adapter(
          :warn,
          { resource: timezone_conversion_log_resource, action: 'timezone_conversion',
            error_message: error.message, date_string:, timezone: },
          "Failed to convert time to facility timezone: #{error.message}",
          { service: 'unified_health_data', date_string:, timezone: }
        )
      end
    end
  end
end
