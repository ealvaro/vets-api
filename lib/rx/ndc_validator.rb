# frozen_string_literal: true

module Rx
  ##
  # Shared NDC (National Drug Code) validation module
  # Provides defense-in-depth validation to prevent path traversal attacks
  #
  # NDC codes are 10-11 digit identifiers for drugs, optionally formatted with dashes
  # Valid formats: 12345678901, 12345-6789-01, 1234-5678-90
  #
  module NdcValidator
    # Valid NDC formats: digits optionally separated by dashes
    # This strict pattern rejects path traversal characters (../, /, \, etc.)
    NDC_FORMAT_REGEX = /\A[0-9]+(-[0-9]+)*\z/

    class InvalidNdcFormatError < StandardError; end

    ##
    # Validates that NDC contains only valid characters (digits and dashes)
    # Safely handles non-string inputs by coercing to string first
    #
    # @param ndc [Object] National Drug Code to validate (will be coerced to String)
    # @return [Boolean] true if valid format
    #
    def valid_ndc_format?(ndc)
      return false if ndc.blank?

      ndc_string = ndc.to_s
      return false unless NDC_FORMAT_REGEX.match?(ndc_string)

      # Validate 10-11 digit length per NDC standard
      digits_only = ndc_string.delete('-')
      digits_only.length.between?(10, 11)
    end

    ##
    # Validates NDC format, raising an error if invalid
    # Use this for defense-in-depth validation at service boundaries
    #
    # @param ndc [Object] National Drug Code to validate
    # @raise [InvalidNdcFormatError] if NDC format is invalid
    #
    def validate_ndc_format!(ndc)
      return if valid_ndc_format?(ndc)

      ndc_for_log = ndc.to_s[0, 50]
      Rails.logger.warn('Rx::NdcValidator: Invalid NDC format detected', ndc: ndc_for_log)
      raise InvalidNdcFormatError, 'Invalid NDC format'
    end
  end
end
