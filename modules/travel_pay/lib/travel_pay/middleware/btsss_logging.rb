# frozen_string_literal: true

require 'logging/helper/data_scrubber'

module TravelPay
  module Middleware
    ##
    # Faraday response middleware that logs scrubbed request/response payloads
    # for debugging and audit purposes. Modeled after VAOS::Middleware::VAOSLogging.
    #
    # Logs structured data (method, URL, status, duration, scrubbed bodies) to
    # Rails.logger, which flows to Datadog via the log agent.
    #
    # PII is detected and replaced using Logging::Helper::DataScrubber, which
    # pattern-matches SSNs, emails, ICNs, phone numbers, etc. in values.
    #
    # Gated by the :travel_pay_btsss_logging Flipper flag.
    #
    class BtsssLogging < Faraday::Middleware
      STATSD_KEY_PREFIX = 'api.travel_pay.btsss.response'

      def call(env)
        start_time = Time.current
        request_body = env.body

        @app.call(env).on_complete do |response_env|
          duration = Time.current - start_time
          level = response_env.status.between?(200, 299) ? :info : :warn
          message = level == :info ? 'BTSSS service call succeeded' : 'BTSSS service call failed'

          log(level, message, log_tags(env, duration, request_body:, response_body: response_env.body))
        end
      rescue Timeout::Error, Faraday::TimeoutError, Faraday::ConnectionFailed => e
        duration = Time.current - start_time
        log(:warn, "BTSSS service call failed - #{e.class}",
            log_tags(env, duration, request_body:))
        raise
      end

      private

      ##
      # Build the structured log hash for a request/response pair.
      #
      # @param env [Faraday::Env] the request environment (always available for metadata)
      # @param duration [Float] elapsed seconds
      # @param request_body [String, Hash, nil] the original request body (captured before Faraday replaces env.body)
      # @param response_body [String, Hash, nil] the response body
      # @return [Hash]
      #
      def log_tags(env, duration, request_body: nil, response_body: nil)
        {
          service_name: 'BTSSS-API',
          http_method: env.method.to_s.upcase,
          url: filtered_url(env.url),
          status: env.status,
          duration:,
          correlation_id: env.request_headers['X-Correlation-ID'],
          request_body: scrub(parse_body(request_body)),
          response_body: scrub(parse_body(response_body))
        }
      end

      ##
      # Strip query parameters from URLs to avoid leaking PII in query strings,
      # and filter identifiers from the path.
      #
      def filtered_url(url)
        base = "#{url.scheme}://#{url.host}#{url.path}"
        StringHelpers.filtered_endpoint_tag(base)
      end

      ##
      # Safely parse a response/request body into a Hash or Array.
      # Returns a deep copy to ensure the original request/response is never mutated.
      #
      def parse_body(body)
        return nil if body.blank?
        return body.deep_dup if body.is_a?(Hash) || body.is_a?(Array)

        JSON.parse(body)
      rescue JSON::ParserError
        '[UNPARSEABLE]'
      end

      ##
      # Scrub PII from a parsed payload using the shared DataScrubber utility.
      #
      def scrub(obj)
        return obj if obj.nil? || obj == '[UNPARSEABLE]'

        Logging::Helper::DataScrubber.scrub(obj)
      end

      def log(level, message, tags)
        Rails.logger.send(level, message, **tags)
      end
    end
  end
end

Faraday::Response.register_middleware btsss_logging: TravelPay::Middleware::BtsssLogging
