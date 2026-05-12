# frozen_string_literal: true

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
      raise Vass::Errors::InvalidVeteranTimeZoneError, 'Veteran time zone is required' if iana.blank?

      zone = Time.find_zone(iana)
      raise Vass::Errors::InvalidVeteranTimeZoneError, 'Unknown veteran time zone' unless zone

      identifier = zone.tzinfo.canonical_identifier
      windows = self.class.mapping[identifier] || self.class.mapping[iana]
      raise Vass::Errors::InvalidVeteranTimeZoneError, 'Unsupported veteran time zone' unless windows

      windows
    end
  end
end
