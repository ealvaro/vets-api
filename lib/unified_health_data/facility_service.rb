# frozen_string_literal: true

require 'common/client/base'
require 'common/exceptions'
require_relative 'facility_configuration'

module UnifiedHealthData
  # Service for fetching VA facility information, specifically timezone data.
  # This is a standalone service for Medical Records, independent of VAOS.
  #
  # Uses the VA Mobile Facilities API: /facilities/v3/facilities/:id
  #
  # Example usage:
  #   service = UnifiedHealthData::FacilityService.new
  #   timezone = service.get_facility_timezone('668')
  #   # => 'America/Los_Angeles'
  #
  class FacilityService < Common::Client::Base
    STATSD_KEY_PREFIX = 'api.uhd.facility'
    CACHE_TTL = 12.hours
    NOT_FOUND_CACHE_TTL = 1.hour
    # Sentinel cached when the facility API returns a true 404 (station not found), so we don't re-hit the API.
    NOT_FOUND_SENTINEL = :facility_not_found

    include Common::Client::Concerns::Monitoring

    configuration UnifiedHealthData::FacilityConfiguration

    # Gets the IANA timezone ID for a facility, with caching.
    #
    # @param station_number [String] The station number (e.g., '668')
    # @return [String, nil] IANA timezone ID (e.g., 'America/Los_Angeles') or nil if not found
    def get_facility_timezone(station_number)
      return nil if station_number.blank?

      facility = get_facility_with_cache(station_number)
      if facility.nil?
        StatsD.increment("#{STATSD_KEY_PREFIX}.timezone_lookup", tags: ['result:facility_not_found'])
        return nil
      end

      # VA Mobile Facilities API returns timezone.zoneId
      timezone = facility.dig(:timezone, :zoneId)
      if timezone.present?
        StatsD.increment("#{STATSD_KEY_PREFIX}.timezone_lookup", tags: ['result:success'])
      else
        StatsD.increment("#{STATSD_KEY_PREFIX}.timezone_lookup", tags: ['result:timezone_missing'])
      end
      timezone
    end

    # Gets facility information with caching.
    # Successful lookups are cached for CACHE_TTL. A 404 response is cached with a
    # shorter TTL to avoid repeated API calls for invalid station numbers, such as
    # test station 989.
    # Other failures, including timeouts, 5xx responses, or unparseable responses
    # that return no facility, are not cached. This allows valid facilities to
    # recover as soon as the upstream service does.
    #
    # @param facility_id [String] The facility/station ID
    # @return [Hash, nil] Facility information or nil if not found/error
    def get_facility_with_cache(facility_id)
      cached = read_cached_facility(facility_id)
      return cached unless cached == :cache_miss

      facility = fetch_facility(facility_id)
      cache_facility(facility_id, facility, CACHE_TTL) if facility
      facility
    rescue Common::Exceptions::BackendServiceException => e
      log_facility_error(facility_id, e)
      # Only a true 404 means the station doesn't exist; cache it to stop repeat calls.
      cache_not_found(facility_id) if e.original_status.to_i == 404
      nil
    rescue => e
      log_facility_error(facility_id, e)
      nil
    end

    # Gets facility information from the API, returning nil on any error.
    #
    # @param facility_id [String] The facility/station ID
    # @return [Hash, nil] Facility information or nil on error
    def get_facility(facility_id)
      fetch_facility(facility_id)
    rescue Common::Exceptions::BackendServiceException, StandardError => e
      log_facility_error(facility_id, e)
      nil
    end

    private

    # Reads the cache and decodes the not-found sentinel.
    # Returns the facility hash, nil (cached not-found), or :cache_miss when absent.
    def read_cached_facility(facility_id)
      cached = Rails.cache.read(cache_key(facility_id))
      return :cache_miss if cached.nil?

      cached == NOT_FOUND_SENTINEL ? nil : cached
    end

    def cache_facility(facility_id, facility, ttl)
      Rails.cache.write(cache_key(facility_id), facility, expires_in: ttl)
    end

    def cache_not_found(facility_id)
      Rails.cache.write(cache_key(facility_id), NOT_FOUND_SENTINEL, expires_in: NOT_FOUND_CACHE_TTL)
    end

    # Performs the raw facility API call. Raises on HTTP errors.
    def fetch_facility(facility_id)
      with_monitoring do
        response = perform(:get, facilities_url(facility_id), {}, headers)
        parse_response(response)
      end
    end

    def facilities_url(facility_id)
      "/facilities/v3/facilities/#{facility_id}"
    end

    def headers
      { 'Content-Type' => 'application/json' }
    end

    def cache_key(facility_id)
      "uhd_facility_#{facility_id}"
    end

    def parse_response(response)
      body = response.body
      return nil if body.blank?

      if body.is_a?(Hash)
        body.with_indifferent_access
      elsif body.is_a?(String)
        JSON.parse(body).with_indifferent_access
      else
        body
      end
    rescue JSON::ParserError => e
      Rails.logger.warn(
        "UHD FacilityService: Failed to parse response body: #{e.message}",
        { service: 'unified_health_data' }
      )
      nil
    end

    def log_facility_error(facility_id, error)
      Rails.logger.warn(
        "UHD FacilityService error fetching facility #{facility_id}: #{error.message}",
        {
          service: 'unified_health_data',
          facility_id:,
          error_class: error.class.name
        }
      )
      # Use error_class tag instead of facility_id to avoid high-cardinality metrics
      # Per-facility details are available in logs
      StatsD.increment("#{STATSD_KEY_PREFIX}.error", tags: ["error_class:#{error.class.name}"])
    end
  end
end
