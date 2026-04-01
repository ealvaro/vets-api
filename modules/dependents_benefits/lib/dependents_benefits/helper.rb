# frozen_string_literal: true

require 'dependents_benefits/helper/decisions'
require 'dependents_benefits/helper/models'

module DependentsBenefits
  # Helper module for processing
  module Helper
    include Decisions
    include Models

    # Returns the component name for monitoring/logging
    #
    # Used as the default component tag value in monitor event tracking.
    # Returns the fully qualified class name for better log filtering and debugging.
    #
    # @return [String] The fully qualified class name
    def component = self.class.name

    # Recursively camelizes all keys in a nested data structure
    #
    # Transforms hash keys to lower camelCase format and recursively processes
    # nested hashes and arrays. Non-hash/array values are returned unchanged.
    #
    # @param data [Hash, Array, Object] The data structure to camelize
    # @return [Hash, Array, Object] The data structure with camelized keys
    def deep_camelize_keys(data)
      case data
      when Hash
        data.transform_keys { |key| key.to_s.camelize(:lower) }
            .transform_values { |value| deep_camelize_keys(value) }
      when Array
        data.map { |item| deep_camelize_keys(item) }
      else
        data
      end
    end

    # Parses a date string into a Time object using the application's time zone.
    #
    # @param date_string [String, nil] The date string to parse
    # @return [Time, nil] Parsed time object or nil if input is blank
    #
    def parse_time(date_string)
      return if date_string.blank?

      Time.zone.parse(date_string.to_s)
    end

    # Normalizes whitespace in a string by replacing consecutive whitespace with single spaces.
    #
    # @param str [String, nil] The string to normalize
    # @return [String, nil] String with normalized whitespace, or nil if input is nil
    #
    def trim_whitespace(str)
      str&.gsub(/\s+/, ' ')
    end

    # stub
    def parent_claim_id
      @parent_claim_id
    end

    # Returns a memoized instance of the DependentsBenefits monitor
    #
    # @return [DependentsBenefits::Monitor] Monitor instance for tracking events and errors
    def monitor
      @monitor ||= DependentsBenefits::Monitor.new(parent_claim_id)
    end

    # Returns a notification email handler for the claim
    #
    # @return [DependentsBenefits::NotificationEmail] Notification email instance
    def notification_email
      @notification_email ||= DependentsBenefits::NotificationEmail.new(parent_claim_id)
    end
  end
end
