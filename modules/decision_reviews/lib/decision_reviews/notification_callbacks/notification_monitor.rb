# frozen_string_literal: true

require 'logging/monitor'

module DecisionReviews
  class NotificationMonitor < Logging::Monitor
    def track_request(error_level, message, metric, call_location: nil, **context) # rubocop:disable Lint/UnusedMethodArgument
      function = extract_function(context)
      tags = (["service:#{service}", "function:#{function}"] + (context[:tags] || [])).uniq
      StatsD.increment(metric, tags:)

      if %w[debug info warn error fatal unknown].include?(error_level.to_s)
        payload = {
          statsd: metric,
          service:,
          function:,
          context:
        }
        Rails.logger.public_send(error_level, message.to_s, payload)
      else
        Rails.logger.error("Invalid log error_level: #{error_level}")
      end
    end

    def log_silent_failure(additional_context, _user_account_uuid = nil, call_location: nil) # rubocop:disable Lint/UnusedMethodArgument
      metric = 'silent_failure'
      message = 'Silent failure!'
      function = extract_function(additional_context)

      payload = {
        statsd: metric,
        service:,
        function:,
        additional_context:
      }

      StatsD.increment(metric, tags: ["service:#{service}", "function:#{function}"])
      Rails.logger.error(message, payload)
    end

    def log_silent_failure_avoided(additional_context, _user_account_uuid = nil, call_location: nil) # rubocop:disable Lint/UnusedMethodArgument
      metric = 'silent_failure_avoided'
      message = 'Silent failure avoided'
      function = extract_function(additional_context)

      payload = {
        statsd: metric,
        service:,
        function:,
        additional_context:
      }

      StatsD.increment(metric, tags: ["service:#{service}", "function:#{function}"])
      Rails.logger.error(message, payload)
    end

    private

    # Read `function` from `callback_metadata` regardless of whether the
    # surrounding context or the metadata hash itself uses symbol or string
    # keys. `VANotify::Notification#callback_metadata` is a JSON-backed
    # column, so the deserialized hash typically has string keys even when
    # the wrapping context uses symbols.
    def extract_function(context)
      metadata = context[:callback_metadata] || context['callback_metadata'] || {}
      metadata[:function] || metadata['function']
    end
  end
end
