# frozen_string_literal: true

module TravelClaim
  ##
  # StatsD helpers for outgoing BTSSS request errors on the v1 travel claim path.
  # Tags failures with error_type for Datadog filtering (timeout, http, empty_response).
  #
  module RequestErrorMetrics
    ERROR_TYPE_TIMEOUT = 'timeout'
    ERROR_TYPE_HTTP = 'http'
    ERROR_TYPE_EMPTY_RESPONSE = 'empty_response'
    TIMEOUT_HTTP_STATUSES = [408, 504].freeze

    module_function

    def increment(facility_type:, error_type:)
      metric = if facility_type.to_s.strip.downcase == 'oh'
                 CheckIn::Constants::OH_STATSD_BTSSS_V1_REQUEST_ERROR
               else
                 CheckIn::Constants::CIE_STATSD_BTSSS_V1_REQUEST_ERROR
               end

      StatsD.increment(metric, tags: ["error_type:#{error_type}"])
    end

    def increment_for_exception(facility_type:, error:)
      increment(facility_type:, error_type: error_type_for(error))
    end

    def error_type_for(error)
      timeout_error?(error) ? ERROR_TYPE_TIMEOUT : ERROR_TYPE_HTTP
    end

    def timeout_error?(error)
      return true if error.is_a?(Common::Exceptions::GatewayTimeout)

      TIMEOUT_HTTP_STATUSES.include?(http_status(error))
    end

    def http_status(error)
      return error.original_status if error.respond_to?(:original_status) && !error.original_status.nil?
      return error.status if error.respond_to?(:status)
      return error.status_code if error.respond_to?(:status_code)

      nil
    end
  end
end
