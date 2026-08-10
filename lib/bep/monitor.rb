# frozen_string_literal: true

require 'logging/monitor'

module BEP
  class Monitor < ::Logging::Monitor
    attr_reader :metric_prefix

    ALLOWLIST = %w[method endpoint_name service].freeze

    def initialize(service_name, allowlist: [], safe_keys: [], metric_prefix: 'api.bep')
      @metric_prefix = metric_prefix
      super(service_name, allowlist: ALLOWLIST + allowlist, safe_keys:)
    end

    ## Emit a log message relevant to an external API call
    #
    # Log message should include the calling class/method, as
    # well as the endpoint being called and some indication
    # of success/failure (e.g. via log level). Should also
    # allow for additional context to be passed by caller.
    #
    # @param method [String] the http method (e.g. GET, POST, PUT, etc)
    # @param endpoint_name [String] the endpoint being called. This does not have
    #      to be the exact path as it might make sense to consolidate several
    #      url paths under a single 'endpoint' for the sake of logging/monitoring
    # @param additional_context [Hash] additional logging context
    # @param call_location [Thread::Backtrace::Location] call location
    def track_api_request(method, endpoint_name, additional_context: {}, call_location: caller_locations.first)
      # perform the api request
      response = yield

      # compile and emit the log message
      # Example message: "BEP::Monitor (bep-persons-api) GET get_relationships: 200 OK"
      message = format_message("#{method.upcase} #{endpoint_name}: #{response.status} #{response.reason_phrase}")
      is_success = response.success?
      log_level = is_success ? :info : :error
      metric_name = is_success ? success_metric_name : failure_metric_name
      track_request(log_level, message, metric_name, call_location:, **additional_context.merge({
                                                                                                  method:,
                                                                                                  endpoint_name:,
                                                                                                  service:
                                                                                                }))

      # make sure to return original response
      response
    rescue => e
      message = format_message("#{method.upcase} #{endpoint_name}: API Error, #{e.message}")
      track_request(:error, message, failure_metric_name, call_location:, **additional_context.merge({
                                                                                                       method:,
                                                                                                       endpoint_name:,
                                                                                                       service:
                                                                                                     }))
      raise e
    end

    protected

    def format_message(msg)
      "#{self.class.name} (#{service}) #{msg}"
    end

    def success_metric_name
      "#{metric_prefix}.success"
    end

    def failure_metric_name
      "#{metric_prefix}.failure"
    end
  end
end
