# frozen_string_literal: true

module Eps
  class ProviderService < BaseService
    # These two use STATSD_PREFIX ('api.vaos'), NOT the STATSD_KEY_PREFIX ('api.eps')
    # this class inherits from Eps::BaseService. That is deliberate and load-bearing:
    # the live metrics are
    #
    #   vets_api.statsd.api_vaos_provider_service_no_params
    #   vets_api.statsd.api_vaos_provider_service_no_self_schedulable
    #
    # 'api.eps.provider_service.*' has never been emitted. Do not "correct" the prefix
    # here without repointing the dashboards that query the api_vaos_* names.
    #
    # StatsD metrics for provider service calls with no parameters
    PROVIDER_SERVICE_NO_PARAMS_METRIC = "#{STATSD_PREFIX}.provider_service.no_params".freeze
    # StatsD metric for when providers are found but none are self-schedulable
    PROVIDER_SERVICE_NO_SELF_SCHEDULABLE_METRIC = "#{STATSD_PREFIX}.provider_service.no_self_schedulable".freeze
    # StatsD metric for provider searches truncated by the pagination page cap
    PROVIDER_SEARCH_PAGE_CAP_METRIC = "#{STATSD_PREFIX}.provider_service.search_page_cap".freeze

    ##
    # Upper bound on provider-services pages followed in one search. The wall-clock timeout
    # alone would allow hundreds of requests against Wellhive if it ever returned a repeating
    # or cycling nextToken; this bounds the blast radius. Hitting it truncates results, which
    # is logged and counted rather than passed off as a complete set.
    #
    MAX_SEARCH_PAGES = 20

    ##
    # Get provider data from EPS
    #
    # @return OpenStruct response from EPS provider endpoint
    #
    def get_provider_service(provider_id:)
      if provider_id.blank?
        log_no_params_metric('get_provider_service')
        raise ArgumentError, 'provider_id is required and cannot be blank'
      end

      with_monitoring do
        response = perform(:get, "/#{config.base_path}/provider-services/#{provider_id}",
                           {}, request_headers_with_correlation_id)

        OpenStruct.new(response.body)
      end
    rescue Eps::ServiceException => e
      handle_eps_error!(e, 'get_provider_service')
      raise e
    end

    def get_provider_services_by_ids(provider_ids:)
      if provider_ids.blank?
        log_no_params_metric('get_provider_services_by_ids')
        return OpenStruct.new(provider_services: [])
      end

      with_monitoring do
        # Build query string manually to get: ?id=val1&id=val2
        # This is required by the backend service (not standard, but necessary)
        query_string = provider_ids.map { |id| "id=#{CGI.escape(id.to_s)}" }.join('&')
        url_with_params = "/#{config.base_path}/provider-services?#{query_string}"
        all_providers = fetch_all_provider_services(initial_url: url_with_params)

        OpenStruct.new(provider_services: all_providers, count: all_providers.length)
      end
    rescue Eps::ServiceException => e
      handle_eps_error!(e, 'get_provider_services_by_ids')
      raise e
    end

    ##
    # Get networks from EPS
    #
    # @return OpenStruct response from EPS networks endpoint
    #
    def get_networks
      with_monitoring do
        response = perform(:get, "/#{config.base_path}/networks", {}, request_headers_with_correlation_id)

        OpenStruct.new(response.body)
      end
    rescue Eps::ServiceException => e
      handle_eps_error!(e, 'get_networks')
      raise e
    end

    ##
    # Get drive times from EPS
    #
    # @param destinations [Hash] Hash of UUIDs mapped to lat/long coordinates
    # @param origin [Hash] Hash containing origin lat/long coordinates
    # @return OpenStruct response from EPS drive times endpoint
    #
    def get_drive_times(destinations:, origin:)
      with_monitoring do
        payload = {
          destinations:,
          origin:
        }

        response = perform(:post, "/#{config.base_path}/drive-times", payload, request_headers_with_correlation_id)

        OpenStruct.new(response.body)
      end
    rescue Eps::ServiceException => e
      handle_eps_error!(e, 'get_drive_times')
      raise e
    end

    ##
    # Retrieves available slots for a specific provider.
    #
    # @param provider_id [String] The unique identifier of the provider
    # @param opts [Hash] Optional parameters for the request
    # @option opts [String] :appointmentTypeId Required. The type of appointment
    # @option opts [String] :startOnOrAfter Required. Start of the time range (ISO 8601 format)
    # @option opts [String] :startBefore Required. End of the time range (ISO 8601 format)
    # @option opts [Hash] Additional optional parameters will be passed through to the request
    #
    # @raise [ArgumentError] If any of appointmentTypeId, startOnOrAfter, or startBefore are missing
    #
    # @return [OpenStruct] Response containing all available slots from all pages
    #
    def get_provider_slots(provider_id, opts = {})
      raise ArgumentError, 'provider_id is required and cannot be blank' if provider_id.blank?

      with_monitoring do
        all_slots = fetch_all_provider_slots(provider_id, opts)
        combined_response = { slots: all_slots, count: all_slots.length }
        OpenStruct.new(combined_response)
      end
    rescue Eps::ServiceException => e
      handle_eps_error!(e, 'get_provider_slots')
      raise e
    end

    ##
    # Search for provider services using NPI and specialty.
    #
    # @param npi [String] NPI number to search for
    # @param specialty [String] Specialty to match (case-insensitive)
    # @param referral_number [String] Optional referral/consultation number for logging
    #
    # @return OpenStruct response containing the first self-schedulable provider service whose
    # individual provider matches the NPI and specialty.
    #
    def search_provider_services(npi:, specialty:, referral_number: nil)
      validate_search_params(npi, specialty, referral_number)

      response = fetch_provider_services(npi)
      all_providers = response.body[:provider_services] || []
      if all_providers.blank?
        log_no_providers_found(npi, referral_number)
        return nil
      end

      self_schedulable_providers = check_self_schedulable_results(all_providers, npi, referral_number)
      return nil if self_schedulable_providers.nil?

      specialty_matches = check_specialty_matches(self_schedulable_providers, specialty, npi, referral_number)
      return nil if specialty_matches.nil?

      OpenStruct.new(specialty_matches.first)
    rescue Eps::ServiceException => e
      handle_eps_error!(e, 'search_provider_services')
      raise e
    end

    ##
    # Search for provider services by geographic location.
    # Uses the EPS nearLocation parameter to find providers within a given radius.
    #
    # When +specialty_ids+ is provided, filtering is delegated to Wellhive via the
    # +specialtyId+ query parameter (server-side, authoritative). When only the
    # legacy +specialty+ string is provided, a best-effort client-side name match
    # is applied instead.
    #
    # @param query [Eps::ProviderSearchQuery] Search criteria (coordinates, radius, and optional
    #   specialty / self-schedulable filters). See {Eps::ProviderSearchQuery}.
    # @return [Array<Hash>] Provider services near the location
    #
    def search_by_location(query)
      lat, lon, radius_miles = validate_location_search_params!(query.coordinates, query.radius)
      normalized_specialty_ids = Array(query.specialty_ids).compact.uniq.presence

      query_params = build_search_params(
        near_location: "#{lat},#{lon}",
        max_miles_from_near: radius_miles,
        is_self_schedulable: query.self_schedulable_only ? true : nil,
        specialty_ids: normalized_specialty_ids
      )

      with_monitoring do
        all_providers = fetch_all_provider_services(
          initial_url: "/#{config.base_path}/provider-services",
          initial_params: query_params
        )
        apply_specialty_filters(all_providers, query.specialty, normalized_specialty_ids,
                                self_schedulable_only: query.self_schedulable_only)
      end
    rescue Eps::ServiceException => e
      handle_eps_error!(e, 'search_by_location')
      raise e
    end

    private

    ##
    # Applies self-schedulable + specialty filtering to the raw provider results.
    #
    # When +normalized_specialty_ids+ is present, Wellhive has already filtered
    # server-side by +specialtyId+; we only apply the self-schedulable filter.
    # Otherwise we fall back to the legacy client-side name-match behavior.
    #
    # When +self_schedulable_only+ is false, phone-only providers are retained
    # (no self-schedulable filtering) so the post-MVP provider list can surface them.
    #
    def apply_specialty_filters(all_providers, specialty, normalized_specialty_ids, self_schedulable_only: true)
      candidates = self_schedulable_only ? filter_self_schedulable(all_providers) : all_providers
      return candidates if normalized_specialty_ids || specialty.blank?

      filter_by_specialty(candidates, specialty)
    end

    ##
    # Fetches every page of a provider-services search.
    #
    # Wellhive's ProviderServiceSearchResult is paginated: +nextToken+ comes back whenever
    # more results exist, and per the spec every other query param is ignored once
    # +nextToken+ is supplied -- so follow-up pages send the token alone. Previously only
    # the first page was read, silently truncating any result set that spilled past it.
    #
    # @param initial_url [String] path for the first page (may already carry a query string)
    # @param initial_params [Hash] query params for the first page
    # @return [Array<Hash>] provider services from every page
    #
    def fetch_all_provider_services(initial_url:, initial_params: {})
      all_providers = []
      next_token = nil
      start_time = Time.current
      pages = 0

      loop do
        url = next_token ? "/#{config.base_path}/provider-services" : initial_url
        params = next_token ? { nextToken: next_token } : initial_params

        response = perform(:get, url, params, request_headers_with_correlation_id)
        body = response.body || {}
        all_providers.concat(extract_provider_services(body))
        pages += 1

        next_token = body[:next_token]
        break if next_token.blank?

        if pages >= MAX_SEARCH_PAGES
          log_provider_search_page_cap(pages, all_providers.length)
          break
        end

        # Checked only between pages: the first page always has to be fetched, and a
        # single-page search should never touch the pagination timeout at all.
        check_provider_search_timeout(start_time)
      end

      all_providers
    end

    ##
    # Records that pagination stopped at the page cap with results still outstanding, so the
    # truncation is visible instead of looking like a complete result set.
    #
    def log_provider_search_page_cap(pages, provider_count)
      StatsD.increment(PROVIDER_SEARCH_PAGE_CAP_METRIC, tags: [COMMUNITY_CARE_SERVICE_TAG])
      Rails.logger.warn(
        "#{CC_APPOINTMENTS}: Provider services pagination hit page cap; results truncated",
        { pages:, provider_count:, max_pages: MAX_SEARCH_PAGES }.merge(common_logging_context)
      )
    end

    def extract_provider_services(body)
      providers = body[:provider_services]
      providers.is_a?(Array) ? providers : []
    end

    ##
    # Guards provider-services pagination against a runaway +nextToken+ loop, mirroring
    # the slots pagination timeout.
    #
    # @param start_time [Time] when pagination started
    # @raise [Common::Exceptions::BackendServiceException] if the timeout is exceeded
    #
    def check_provider_search_timeout(start_time)
      timeout_seconds = config.pagination_timeout_seconds
      return unless Time.current - start_time > timeout_seconds

      Rails.logger.error("#{CC_APPOINTMENTS}: Provider services pagination timeout",
                         { timeout_seconds: }.merge(common_logging_context))
      raise Common::Exceptions::BackendServiceException.new(
        'PROVIDER_SEARCH_TIMEOUT',
        source: self.class.to_s
      )
    end

    ##
    # Fetches all provider slots by paginating through responses
    #
    # @param provider_id [String] The unique identifier of the provider
    # @param opts [Hash] Request options including required parameters
    # @return [Array] All slots from all pages
    #
    def fetch_all_provider_slots(provider_id, opts)
      all_slots = []
      next_token = nil
      start_time = Time.current

      loop do
        check_pagination_timeout(start_time, provider_id)
        params = build_slot_params(next_token, opts)
        response = perform(:get, "/#{config.base_path}/provider-services/#{provider_id}/slots", params,
                           request_headers_with_correlation_id)

        current_response = response.body
        all_slots.concat(current_response[:slots]) if current_response[:slots].present?

        next_token = current_response[:next_token]
        break if next_token.blank?
      end

      all_slots
    end

    ##
    # Logs StatsD metric and Rails log for provider service calls with no parameters
    #
    # @param method_name [String] The name of the method being called
    #
    def log_no_params_metric(method_name)
      # Log StatsD metric for monitoring
      StatsD.increment(PROVIDER_SERVICE_NO_PARAMS_METRIC, tags: [COMMUNITY_CARE_SERVICE_TAG])

      # Log Rails warning with context
      log_data = {
        method: method_name,
        service: 'eps_provider_service'
      }
      log_data[:user_uuid] = @user.uuid if @user&.uuid

      Rails.logger.warn("#{CC_APPOINTMENTS}: Provider service called with no parameters", log_data)
    end

    ##
    # Validates required search parameters
    #
    # @param npi [String] Provider NPI
    # @param specialty [String] Provider specialty
    # @raise [ArgumentError] If any required parameter is blank
    #
    def validate_search_params(npi, specialty, referral_number = nil)
      validate_npi_param(npi, specialty, referral_number)
      validate_specialty_param(specialty, npi, referral_number)
    end

    ##
    # Fetches provider services from EPS API
    #
    # @param npi [String] Provider NPI
    # @return [Object] Response from EPS API
    #
    def fetch_provider_services(npi)
      if npi.blank?
        log_no_params_metric('fetch_provider_services')
        raise ArgumentError, 'npi is required and cannot be blank'
      end

      with_monitoring do
        query_params = { npi:, isSelfSchedulable: true }
        perform(:get, "/#{config.base_path}/provider-services", query_params,
                request_headers_with_correlation_id)
      end
    end

    ##
    # Checks for self-schedulable providers and filters results
    #
    # @param all_providers [Array] All providers from EPS response
    # @param npi [String] Provider NPI
    # @return [Array, nil] Self-schedulable providers or nil if none found
    #
    def check_self_schedulable_results(all_providers, npi, referral_number = nil)
      if all_providers.blank?
        Rails.logger.warn("#{CC_APPOINTMENTS}: No providers found for NPI", **common_logging_context)
        return nil
      end

      self_schedulable_providers = filter_self_schedulable(all_providers)
      if self_schedulable_providers.empty?
        StatsD.increment(PROVIDER_SERVICE_NO_SELF_SCHEDULABLE_METRIC, tags: [COMMUNITY_CARE_SERVICE_TAG])
        Rails.logger.error("#{CC_APPOINTMENTS}: No self-schedulable providers found for NPI", **common_logging_context)
        log_personal_information_error('eps_provider_no_self_schedulable', {
                                         npi:,
                                         referral_number:,
                                         failure_reason: 'No self-schedulable providers found ' \
                                                         '(digital/direct booking disabled)'
                                       })
        return nil
      end

      self_schedulable_providers
    end

    ##
    # Checks for specialty matches among self-schedulable providers
    #
    # @param self_schedulable_providers [Array] Self-schedulable providers
    # @param specialty [String] Specialty to match
    # @return [Array, nil] Specialty matches or nil if none found
    #
    def check_specialty_matches(self_schedulable_providers, specialty, npi, referral_number = nil)
      specialty_matches = filter_by_specialty(self_schedulable_providers, specialty)
      if specialty_matches.empty?
        Rails.logger.warn("#{CC_APPOINTMENTS}: No specialty matches found.", **common_logging_context)
        log_personal_information_error('eps_provider_specialty_mismatch', {
                                         npi:,
                                         referral_number:,
                                         search_params: { specialty: },
                                         failure_reason: "No providers match specialty '#{specialty}'"
                                       })
        return nil
      end

      specialty_matches
    end

    ##
    # Filters providers to only those that are self-schedulable
    #
    # A provider is self-schedulable if:
    # 1. features.isDigital is true
    # 2. features.directBooking.isEnabled is true
    #
    # Note: The isSelfSchedulable query parameter in fetch_provider_services
    # handles appointment type filtering at the EPS API level.
    #
    # @param providers [Array] List of providers from EPS response
    # @return [Array] All self-schedulable providers, or empty array if none found
    #
    def filter_self_schedulable(providers)
      providers.select do |provider|
        provider.dig(:features, :is_digital) == true &&
          provider.dig(:features, :direct_booking, :is_enabled) == true
      end
    end

    ##
    # Filters providers by specialty
    #
    # @param providers [Array] List of providers from EPS response
    # @param specialty [String] Specialty to match
    # @return [Array] Providers matching the specialty
    #
    def filter_by_specialty(providers, specialty)
      providers.select do |provider|
        specialty_matches?(provider, specialty)
      end
    end

    ##
    # Checks if pagination has exceeded the timeout limit
    #
    # @param start_time [Time] When pagination started
    # @param provider_id [String] Provider identifier for error logging
    # @raise [Common::Exceptions::BackendServiceException] If timeout exceeded
    #
    def check_pagination_timeout(start_time, provider_id)
      timeout_seconds = config.pagination_timeout_seconds
      return unless Time.current - start_time > timeout_seconds

      error_data = {
        provider_id:,
        timeout_seconds:
      }.merge(common_logging_context)
      Rails.logger.error("#{CC_APPOINTMENTS}: Provider slots pagination timeout", error_data)
      raise Common::Exceptions::BackendServiceException.new(
        'PROVIDER_SLOTS_TIMEOUT',
        source: self.class.to_s
      )
    end

    ##
    # Builds parameters for slot request based on token availability
    #
    # For initial requests (next_token is nil), validates all required parameters including appointmentId.
    # For pagination requests (next_token is present), includes both nextToken and appointmentId.
    # The appointmentId is guaranteed to exist in opts when next_token is present, since next_token
    # only exists after a successful initial request that required appointmentId.
    #
    # @param next_token [String] Token for pagination (only present for subsequent requests)
    # @param opts [Hash] Original request options containing appointmentId and other required params
    # @return [Hash] Parameters for the API request
    #
    def build_slot_params(next_token, opts)
      return { nextToken: next_token, appointmentId: opts[:appointmentId] } if next_token

      required_params = %i[appointmentTypeId startOnOrAfter startBefore appointmentId]
      missing_params = required_params - opts.keys

      raise ArgumentError, "Missing required parameters: #{missing_params.join(', ')}" if missing_params.any?

      opts
    end

    ##
    # Check if provider's specialty matches the requested specialty (case-insensitive)
    #
    # @param provider [Hash] Provider data from EPS response
    # @param specialty [String] Requested specialty to match against
    # @return [Boolean] True if specialty matches, false otherwise
    #
    def specialty_matches?(provider, specialty)
      return false if provider[:specialties].blank? || specialty.blank?

      provider[:specialties].any? do |provider_specialty|
        provider_specialty[:name].to_s.casecmp?(specialty.to_s)
      end
    end

    ##
    # Builds search parameters from the given input parameters.
    #
    # @param params [Hash] A hash containing search filter keys:
    #   - :search_text [String] the text to search for.
    #   - :appointment_id [String] the appointment identifier.
    #   - :npi [String] the National Provider Identifier.
    #   - :network_id [String] the network identifier.
    #   - :max_miles_from_near [Integer] the maximum allowable miles from the specified location.
    #   - :near_location [String] the location reference for proximity.
    #   - :organization_names [Array<String>] an array of organization names.
    #   - :specialty_ids [Array<String>] an array of NUCC Healthcare Provider
    #     Taxonomy codes (e.g. +'207Q00000X'+ for Family Medicine). Sent to
    #     Wellhive as the +specialtyId+ query param (singular -- Wellhive
    #     accepts repeated +specialtyId=...&specialtyId=...+ values).
    #   - :visit_modes [Array<String>] an array of visit mode options.
    #   - :include_inactive [Boolean] flag to include inactive records.
    #   - :digital_or_not [Boolean] flag indicating digital capability.
    #   - :is_self_schedulable [Boolean] flag for self-schedulability.
    #   - :next_token [String] token for pagination.
    #
    # @return [Hash] a hash of search parameters with nil values removed.
    def build_search_params(params)
      {
        searchText: params[:search_text],
        appointmentId: params[:appointment_id],
        npi: params[:npi],
        networkId: params[:network_id],
        maxMilesFromNear: params[:max_miles_from_near],
        nearLocation: params[:near_location],
        organizationNames: params[:organization_names],
        specialtyId: params[:specialty_ids],
        visitModes: params[:visit_modes],
        includeInactive: params[:include_inactive],
        digitalOrNot: params[:digital_or_not],
        isSelfSchedulable: params[:is_self_schedulable],
        nextToken: params[:next_token]
      }.compact
    end

    def validate_location_search_params!(coordinates, radius)
      latitude = coordinates&.dig(:latitude)
      longitude = coordinates&.dig(:longitude)
      raise ArgumentError, 'latitude is required' if latitude.blank?
      raise ArgumentError, 'longitude is required' if longitude.blank?

      [Float(latitude), Float(longitude), Integer(radius.presence || 25)]
    end

    def validate_npi_param(npi, specialty, referral_number)
      return if npi.present?

      log_personal_information_error('eps_provider_npi_missing', {
                                       referral_number:,
                                       search_params: { specialty: },
                                       failure_reason: 'NPI parameter is blank'
                                     })
      raise ArgumentError, 'Provider NPI is required and cannot be blank'
    end

    def validate_specialty_param(specialty, npi, referral_number)
      return if specialty.present?

      log_personal_information_error('eps_provider_specialty_missing', {
                                       npi:,
                                       referral_number:,
                                       failure_reason: 'Specialty parameter is blank'
                                     })
      raise ArgumentError, 'Provider specialty is required and cannot be blank'
    end

    def log_no_providers_found(npi, referral_number = nil)
      log_personal_information_error('eps_provider_no_providers_found', {
                                       npi:,
                                       referral_number:,
                                       failure_reason: 'No providers returned from EPS API for NPI'
                                     })
    end

    ##
    # Logs personal information when provider service errors occur
    #
    # @param error_class [String] The error class identifier
    # @param data [Hash] Personal data to log (npi, referral_number, etc.)
    #
    def log_personal_information_error(error_class, data)
      # Use create (not create!) so logging failures don't break the main flow
      PersonalInformationLog.create(
        error_class:,
        data: {
          npi: data[:npi],
          referral_number: data[:referral_number],
          user_uuid: data[:user_uuid] || @user&.uuid,
          search_params: data[:search_params],
          failure_reason: data[:failure_reason]
        }.compact
      )
    end

    ##
    # Returns common logging context used throughout provider service logging
    #
    # @return [Hash] Common logging context with controller, station_number, eps_trace_id, and user_uuid
    def common_logging_context
      {
        controller: controller_name,
        station_number:,
        eps_trace_id:,
        user_uuid: user&.uuid
      }
    end
  end

  # Mirrors the middleware-defined EPS exception so callers can rely on
  # BackendServiceException fields (e.g., original_status, original_body).
  class ServiceException < Common::Exceptions::BackendServiceException; end unless defined?(Eps::ServiceException)
end
