# frozen_string_literal: true

module TravelClaim
  ##
  # StatsD helpers for outgoing BTSSS request errors on the v1 travel claim path.
  # Tags failures with error_type (timeout, http, empty_response) and source
  # (auth vs btsss) for Datadog filtering.
  #
  module RequestErrorMetrics
    ERROR_TYPE_TIMEOUT = 'timeout'
    ERROR_TYPE_HTTP = 'http'
    ERROR_TYPE_EMPTY_RESPONSE = 'empty_response'
    SOURCE_AUTH = 'auth'
    SOURCE_BTSSS = 'btsss'
    STEP_FIND_OR_ADD_APPOINTMENT = 'find_or_add_appointment'
    STEP_CREATE_CLAIM = 'create_claim'
    TIMEOUT_HTTP_STATUSES = [408, 504].freeze

    module_function

    def increment(facility_type:, error_type:, source: nil, step: nil)
      metric = if facility_type.to_s.strip.downcase == 'oh'
                 CheckIn::Constants::OH_STATSD_BTSSS_V1_REQUEST_ERROR
               else
                 CheckIn::Constants::CIE_STATSD_BTSSS_V1_REQUEST_ERROR
               end

      StatsD.increment(metric, tags: build_tags(error_type:, source:, step:))
    end

    def increment_for_exception(facility_type:, error:, source: nil, step: nil)
      increment(facility_type:, error_type: error_type_for(error), source:, step:)
    end

    def build_tags(error_type:, source: nil, step: nil)
      tags = ["error_type:#{error_type}"]
      tags << "source:#{source}" if source.present?
      tags << "step:#{step}" if step.present?
      tags
    end

    def error_type_for(error)
      timeout_error?(error) ? ERROR_TYPE_TIMEOUT : ERROR_TYPE_HTTP
    end

    def timeout_error?(error)
      return true if error.is_a?(Common::Exceptions::GatewayTimeout)
      return true if error.is_a?(Faraday::TimeoutError)
      return true if error.is_a?(Timeout::Error)

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
