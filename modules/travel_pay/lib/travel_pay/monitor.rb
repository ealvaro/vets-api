# frozen_string_literal: true

require 'logging/monitor'

module TravelPay
  ##
  # Centralized monitoring for the TravelPay module.
  #
  # Provides structured logging + StatsD metrics through a single interface,
  # replacing scattered raw StatsD calls across clients, controllers, and services.
  #
  # @example Tracking an upstream API response time (in service clients)
  #   monitor.track_response_time('claims', 'get_all') { connection.get(...) }
  #
  # @example Tracking an operation outcome (in controllers/services)
  #   monitor.track_request(:info, 'SMOC create success', 'travel_pay.claims.smoc.create',
  #                         tags: ['result:success'])
  #
  class Monitor < ::Logging::Monitor
    STATSD_KEY_PREFIX = 'travel_pay'

    ALLOWLIST = %w[
      tags
      correlation_id
      duration
      appointment_date_time
      facility_station_number
      expense_type
      expense_id
      claim_id
      request_id
      error
      code
      status
      loa
      is_veteran
      has_facilities
    ].freeze

    def initialize
      super('travel-pay', allowlist: ALLOWLIST)
    end

    ##
    # Logs a message through the monitor's filtering pipeline without
    # emitting a StatsD metric. Use for informational/trace logging
    # that doesn't warrant a counter (e.g. correlation IDs, operation progress).
    #
    # @param level [Symbol] the log level (:info, :warn, :error, :debug)
    # @param message [String] the message to log
    # @param context [Hash] additional context (filtered through allowlist)
    #
    def log(level, message, **context)
      function, file, line = parse_caller(context.delete(:call_location))
      filtered_context = scrub(filter_params(context, allowlist:), safe_keys: @safe_keys)

      payload = { service:, function:, file:, line:, context: filtered_context }
      Rails.logger.public_send(level, message.to_s, **payload)
    end

    ##
    # Wraps a block, measures elapsed time via StatsD.measure.
    # Used by service clients to track upstream API response times.
    #
    # @param service [String] the service category (e.g. 'claims', 'appointments')
    # @param tag_value [String] the operation tag (e.g. 'get_all', 'create')
    # @return the result of the yielded block
    #
    def track_response_time(service, tag_value)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      result
    rescue => e
      raise
    ensure
      elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      metric = "#{STATSD_KEY_PREFIX}.#{service}.response_time"
      status = e ? 'failure' : 'success'
      StatsD.measure(metric, elapsed_time, tags: ["travel_pay:#{tag_value}", "status:#{status}"])
    end
  end
end
