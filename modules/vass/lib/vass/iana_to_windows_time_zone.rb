# frozen_string_literal: true

# vass.rb eagerly requires this file during Bundler.require, before the app's
# top-level lib/ is on $LOAD_PATH, so require_relative (not require) is needed.
require_relative '../../../../lib/logging/helper/data_scrubber'

module Vass
  ##
  # Maps IANA time zone identifiers (from browsers) to Windows time zone IDs
  # expected by the external VASS SaveAppointment API.
  #
  # Data is sourced from Unicode CLDR windowsZones (US + common territories and
  # frequently used zones). Extend {config/iana_to_windows_time_zone.yml} for
  # additional IANA identifiers.
  #
  class IanaToWindowsTimeZone
    CONFIG_PATH = File.expand_path('../../config/iana_to_windows_time_zone.yml', __dir__).freeze

    raw_mapping = YAML.safe_load_file(CONFIG_PATH)
    unless raw_mapping.is_a?(Hash)
      raise Vass::Errors::ConfigurationError, 'iana_to_windows_time_zone.yml must be a Hash'
    end

    MAPPING = raw_mapping.transform_keys(&:to_s).transform_values(&:to_s).freeze

    class << self
      ##
      # @param iana_string [String] IANA zone id (e.g. "America/New_York")
      # @return [String] Windows time zone id (e.g. "Eastern Standard Time")
      # @raise [Vass::Errors::InvalidVeteranTimeZoneError] if blank, unknown IANA, or unmapped
      #
      def windows_id_for!(iana_string)
        new(iana_string).windows_id!
      end

      def mapping
        MAPPING
      end
    end

    def initialize(iana_string)
      @iana_string = iana_string
    end

    ##
    # @return [String]
    # @raise [Vass::Errors::InvalidVeteranTimeZoneError]
    #
    def windows_id!
      iana = @iana_string.to_s.strip
      fail_invalid!('blank', 'Veteran time zone is required') if iana.blank?

      zone = Time.find_zone(iana)
      fail_invalid!('unknown_iana', 'Unknown veteran time zone', iana: scrub_zone(iana)) unless zone

      identifier = zone.tzinfo.canonical_identifier
      windows = self.class.mapping[identifier] || self.class.mapping[iana]
      unless windows
        fail_invalid!('unmapped', 'Unsupported veteran time zone',
                      iana: scrub_zone(iana), canonical_identifier: identifier)
      end

      windows
    end

    private

    ##
    # Raises with the rejection reason and the scrubbed offending identifier
    # (so a missing IANA/Windows mapping can be added to
    # {config/iana_to_windows_time_zone.yml}) attached. The caller logs the
    # single audit entry; keeping logging out of here avoids double-logging.
    #
    # @param reason [String] Why the zone was rejected: 'blank', 'unknown_iana', 'unmapped'
    # @param message [String] Client-safe error message
    # @param metadata [Hash] Zone identifiers (iana, canonical_identifier) for diagnosis
    # @raise [Vass::Errors::InvalidVeteranTimeZoneError]
    #
    def fail_invalid!(reason, message, **metadata)
      raise Vass::Errors::InvalidVeteranTimeZoneError.new(message, reason:, log_metadata: metadata)
    end

    ##
    # Scrubs and bounds the client-supplied zone string before logging.
    #
    # @param value [String] Raw IANA zone string from the request
    # @return [String] Scrubbed value truncated to a loggable length
    #
    def scrub_zone(value)
      ::Logging::Helper::DataScrubber.scrub(value.to_s).truncate(64)
    end
  end
end
