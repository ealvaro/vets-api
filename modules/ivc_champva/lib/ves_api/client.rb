# frozen_string_literal: true

require 'json'
require 'common/client/base'
require 'ivc_champva/monitor'
require_relative 'configuration'

module IvcChampva
  module VesApi
    class VesApiError < StandardError; end

    # Raised when VES times out or the connection fails.
    class VesApiTimeoutError < VesApiError; end

    # Raised when VES returns a 200 but no ICNs yet — application is still being processed.
    # Callers should treat this as a transient condition and retry later.
    class VesApplicationPendingError < StandardError; end

    # TODO: define Message response structure

    class Client < Common::Client::Base
      configuration IvcChampva::VesApi::Configuration

      def settings
        Settings.ivc_champva_ves_api
      end

      ##
      # Returns the OHI API key, falling back to the standard api_key if not configured
      #
      # @return [String] the API key for OHI requests
      def ohi_api_key
        settings.ohi_api_key.presence || settings.api_key
      end

      ##
      # HTTP POST call to the VES VFMP CHAMPVA Application service to submit a 10-10d application.
      #
      # @param transaction_uuid [string] the UUID for the transaction (sent in header)
      # @param ves_request_data [IvcChampva::VesRequest] preformatted request data
      def submit_1010d(transaction_uuid, ves_request_data)
        resp = connection.post("#{config.base_path}/ves-vfmp-app-svc/champva-applications") do |req|
          req.headers = headers(transaction_uuid, settings.api_key)
          req.body = ves_request_data.to_json
        end

        # Log with application_uuid (which equals form_uuid) for consistent tracking
        application_uuid = extract_application_uuid(ves_request_data)
        monitor.track_ves_response(application_uuid, resp.status, resp.body)

        raise "response code: #{resp.status}, response body: #{resp.body}" unless resp.status == 200

        resp
      rescue => e
        raise VesApiError, e.message.to_s
      end

      ##
      # HTTP POST call to the VES VFMP service to submit a 10-7959c OHI certification.
      #
      # @param transaction_uuid [string] the UUID for the transaction (sent in header)
      # @param ves_request_data [IvcChampva::VesOhiRequest] preformatted request data
      # @return [Faraday::Response] the response from VES
      # @raise [VesApiError] if the response status is not 200
      def submit_7959c(transaction_uuid, ves_request_data)
        resp = connection.post("#{config.base_path}/ves-vfmp-app-svc/champva-insurance-form") do |req|
          req.headers = headers(transaction_uuid, ohi_api_key)
          req.body = ves_request_data.to_json
        end

        # Log with application_uuid (which equals form_uuid) for consistent tracking
        application_uuid = extract_application_uuid(ves_request_data)
        monitor.track_ves_response(application_uuid, resp.status, resp.body)

        raise "response code: #{resp.status}, response body: #{resp.body}" unless resp.status == 200

        resp
      rescue => e
        raise VesApiError, e.message.to_s
      end

      ##
      # Assembles headers for VES API requests
      #
      # @param transaction_uuid [string] the transaction UUID
      # @param key [string] the API key to use
      # @return [Hash] the headers
      def headers(transaction_uuid, key)
        {
          :content_type => 'application/json',
          'apiKey' => key,
          'transactionUUId' => transaction_uuid.to_s
        }
      end

      ##
      # retreive a monitor for tracking
      #
      # @return [IvcChampva::Monitor]
      #
      def monitor
        @monitor ||= IvcChampva::Monitor.new
      end

      ##
      # Extracts application_uuid from the VES request data.
      # Handles both VesRequest objects (with accessor) and Hash objects (from retries).
      #
      # @param ves_request_data [VesRequest, VesOhiRequest, Hash] the request data
      # @return [String, nil] the application UUID
      def extract_application_uuid(ves_request_data)
        if ves_request_data.respond_to?(:application_uuid)
          ves_request_data.application_uuid
        elsif ves_request_data.is_a?(Hash)
          ves_request_data['application_uuid'] || ves_request_data['applicationUUID']
        end
      end

      ##
      # Retrieve ICNs/person mapping for a given VES transaction UUID
      #
      # @param transaction_uuid [String] the transaction UUID to query
      # @return [Array<Hash>] array of person records (icn, personUUID, personType)
      def get_icns_for_transaction(transaction_uuid)
        url = "#{config.base_path}/ves-vfmp-app-svc/champva-applications/vfmp-txn-request-uuid/#{transaction_uuid}"
        resp = connection.get(url) do |req|
          req.headers = icn_lookup_headers(transaction_uuid)
        end

        monitor.track_ves_response('icn_lookup', resp.status, nil)

        raise "response code: #{resp.status}" unless resp.status == 200

        parsed = JSON.parse(resp.body)
        data = parsed['data'] || []

        raise VesApplicationPendingError, 'No ICNs returned — application may not be processed yet' if data.empty?

        data
      rescue VesApplicationPendingError
        raise
      rescue => e
        raise VesApiError, e.message.to_s
      end

      ##
      # Fetch CHAMPVA eligibility for a given ICN from the VES EE Summary service.
      #
      # The applicant's CHAMPVA status/reason is at:
      #   data['vfmpProgramsInfo']['relationships'][]['champvaEligibilities'][]['status'] / ['reason']
      # The sponsor's CHAMPVA status/reason is nested within each eligibility at:
      #   ...['champvaEligibilities'][]['sponsor']['champvaStatus'] / ['champvaReason']
      #
      # @param icn [String] the person's Integration Control Number
      # @param dataset [String] EE Summary dataset (default CSTChampvaEligibility)
      # @param region_id_or_offset [String, nil] optional timezone region/offset (e.g. 'GMT-6')
      # @return [Hash] the parsed 'data' hash from VES
      # @raise [VesApplicationPendingError] if VES returns 200 but no data (still processing)
      # @raise [VesApiTimeoutError] on timeout or connection failure
      # @raise [VesApiError] on non-200 response or unexpected error
      def get_ee_summary(icn:, dataset: 'CSTChampvaEligibility', region_id_or_offset: nil)
        params = { id: icn }
        params[:regionIdOrOffset] = region_id_or_offset if region_id_or_offset.present?

        resp = connection.get("#{config.base_path}/ves-ee-summary-svc/eesummary/#{dataset}", params) do |req|
          req.headers = ee_summary_headers
        end

        monitor.track_ves_response('ee_summary', resp.status, nil)

        raise "response code: #{resp.status}" unless resp.status == 200

        parsed = JSON.parse(resp.body)
        data = parsed['data']

        if data.nil?
          raise VesApplicationPendingError, 'No EE summary data returned — application may not be processed yet'
        end

        data
      rescue VesApplicationPendingError
        raise
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Net::OpenTimeout, Net::ReadTimeout => e
        raise VesApiTimeoutError, e.message.to_s
      rescue => e
        raise VesApiError, e.message.to_s
      end

      private

      ##
      # Assembles headers for ICN lookup requests. Omits the apiKey header when no key is
      # configured (e.g. staging environments where the key is not required).
      #
      # @param transaction_uuid [String] the transaction UUID
      # @return [Hash] the headers
      def icn_lookup_headers(transaction_uuid)
        h = { :content_type => 'application/json', 'transactionUUId' => transaction_uuid.to_s }
        h['apiKey'] = settings.api_key if settings.api_key.present?
        h
      end

      ##
      # Assembles headers for EE Summary service requests. No transactionUUId required.
      # Omits apiKey when not configured (e.g. staging).
      #
      # @return [Hash] the headers
      def ee_summary_headers
        h = { :content_type => 'application/json', 'accept' => 'application/json' }
        h['apiKey'] = settings.api_key if settings.api_key.present?
        h
      end
    end
  end
end
