# frozen_string_literal: true

module Validations
  module Validator
    # Validates US zip codes against format and known values.
    #
    # Accepts either 5-digit zip codes (e.g., 12345) or ZIP+4 values
    # (e.g., 12345-6789). ZIP+4 input is validated by checking only the
    # first 5 digits against {StdZipcode}.
    class ZipcodeValidator
      # Regular expression pattern for valid US zipcode format
      #
      # Matches 5-digit zipcodes (12345) or 5+4 format (12345-6789)
      #
      # Using string anchors (\A and \z) instead of line anchors (^ and $)
      # to prevent potential security issues with multi-line input.
      #
      # @return [Regexp]
      ZIPCODE_PATTERN = /\A(\d{5})(-\d{4})?\z/

      # Cache key for the in-memory set of known zip codes.
      #
      # @return [String]
      ZIPCODE_CACHE_KEY = 'validations:std_zipcode:zip_code:list'

      # Cache TTL for known zip codes.
      #
      # @return [ActiveSupport::Duration]
      ZIPCODE_CACHE_TTL = 1.day

      # Race-condition TTL used while refreshing the cached zip code set.
      #
      # @return [ActiveSupport::Duration]
      ZIPCODE_CACHE_RACE_TTL = 10.seconds

      # Validates a zipcode
      #
      # @param zipcode [String] The zipcode to validate
      # @return [Hash] { zip_is_valid: Boolean, zipcode: String, message: String }
      def self.validate(zipcode)
        new(zipcode).validate
      end

      attr_reader :zipcode, :message

      # Initialize validator with a zipcode
      # Input is normalized by converting to String and trimming whitespace.
      #
      # @param zipcode [String] The zipcode to validate
      def initialize(zipcode)
        @zipcode = zipcode.to_s.strip
      end

      # Validates the zipcode and returns result hash
      #
      # @return [Hash] Hash with zipcode, zip_is_valid flag, and validation message
      def validate
        {
          zip_is_valid: valid?, # drop-in replacement for zip_is_valid in IncomeLimitsController
          zipcode:,
          message:
        }
      end

      # Checks if zipcode is valid
      #
      # Validates format and checks existence in standard zipcodes database.
      # Uses only the 5-digit part for database lookup.
      #
      # @return [Boolean] True if zipcode is valid, false otherwise
      def valid?
        if zipcode.blank?
          @message = 'Zipcode is required'
          return false
        end

        zip = ZIPCODE_PATTERN.match(zipcode)
        if zip.blank?
          @message = 'Invalid zipcode'
          return false
        end

        valid = cached_zipcodes
        unless valid.include?(zip[1])
          @message = 'Zipcode does not exist'
          return false
        end

        @message = 'Valid zipcode'
        true
      end

      private

      # Returns cached set of known 5-digit zip codes.
      #
      # @return [Set<String>]
      def cached_zipcodes
        Rails.cache.fetch(
          ZIPCODE_CACHE_KEY,
          expires_in: ZIPCODE_CACHE_TTL,
          race_condition_ttl: ZIPCODE_CACHE_RACE_TTL
        ) do
          StdZipcode.distinct.pluck(:zip_code).to_set
        end
      end
    end
  end
end
