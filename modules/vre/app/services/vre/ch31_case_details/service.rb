# frozen_string_literal: true

module VRE
  module Ch31CaseDetails
    class Service < VRE::Service
      configuration VRE::Ch31CaseDetails::Configuration

      class Ch31CaseDetailsError < StandardError; end

      STATSD_KEY_PREFIX = 'api.res.case_details'
      SERVICE_UNAVAILABLE_ERROR = 'APNX-1-4187-000'

      def initialize(icn)
        super()
        raise Common::Exceptions::ParameterMissing, 'ICN' if icn.blank?

        @icn = icn
      end

      # Requests current user's Ch31 case details from RES.
      # Raises Common::Exceptions::BackendServiceException on an upstream error
      # response, or Common::Exceptions::BadGateway when RES returns a
      # malformed (non-JSON) body.
      #
      # @return [VRE::Ch31CaseDetails::Response]
      #
      def get_details
        raw_response = send_to_res(payload: { icn: @icn }.to_json)
        raise_malformed_response! unless raw_response.body.is_a?(Hash)

        VRE::Ch31CaseDetails::Response.new(raw_response.status, raw_response)
      rescue Common::Exceptions::BackendServiceException => e
        log_error(e)
        service_unavailable?(e)
        no_app_in_res!(e)
        raise e
      end

      private

      def api_path
        'get-ch31-case-details'
      end

      def raise_malformed_response!
        monitor.track_request(
          :error,
          'Failed to retrieve Ch. 31 case details: malformed non-JSON response body',
          "#{STATSD_KEY_PREFIX}.get_details.error",
          backtrace: caller
        )
        raise Common::Exceptions::BadGateway.new(
          detail: 'RES returned a non-JSON response body',
          source: 'VRE::Ch31CaseDetails::Service#get_details'
        )
      end

      def log_error(e)
        body = e.original_body
        message = body.is_a?(Hash) ? (body['errorMessageList'] || body['error']) : body
        monitor.track_request(
          :error,
          "Failed to retrieve Ch. 31 case details: #{message}",
          "#{STATSD_KEY_PREFIX}.get_details.error",
          backtrace: e.backtrace
        )
      end

      def service_unavailable?(e)
        body = e.original_body
        return false unless body.is_a?(Hash) && body['error'] == SERVICE_UNAVAILABLE_ERROR

        raise e.class.new('RES_CH31_CASE_DETAILS_503', e.response_values)
      end

      def no_app_in_res!(e)
        body = e.original_body
        return unless body.is_a?(Hash) && body.dig('errors', 0, 'code') == 'NO_APP_IN_RES'

        raise e.class.new('NO_APP_IN_RES', e.response_values, e.original_status, e.original_body)
      end

      def monitor
        @monitor ||= Logging::Monitor.new('res-ch31-case-details', allowlist: %w[backtrace])
      end
    end
  end
end
