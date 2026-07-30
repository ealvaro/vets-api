# frozen_string_literal: true

require 'va_profile/service'
require 'source_app_middleware'

module VAProfile
  class Stats
    STATSD_KEY_PREFIX = 'api.va_profile'
    FINAL_SUCCESS = %w[COMPLETED_SUCCESS COMPLETED_NO_CHANGES_DETECTED].freeze
    FINAL_FAILURE = %w[REJECTED COMPLETED_FAILURE].freeze
    KNOWN_CONTACT_TYPES = %w[address email telephone].freeze
    UNKNOWN_SOURCE_APP = 'unknown'

    class << self
      # Triggers the associated StatsD.increment method for the VAProfile buckets that are
      # initialized in the config/initializers/statsd.rb file.
      #
      # @param *args [String] A variable number of string arguments. Each one represents
      #   a bucket in StatsD.  For example passing in ('policy', 'success') would increment
      #   the 'api.va_profile.policy.success' bucket
      #
      def increment(*args)
        buckets = args.map(&:downcase).join('.')

        StatsD.increment("#{STATSD_KEY_PREFIX}.#{buckets}")
      end

      # If the passed response contains a transaction status that is in one of the final
      # success or failure states, it increments the associated StatsD bucket.
      #
      # @param response [FaradayObject] The raw response from the Faraday HTTP call
      # @param bucket1 [String] The VAProfile bucket to increment.  This bucket must
      #   already be initialized in config/initializers/statsd.rb.
      # @param path [String, nil] The request path (e.g. 'telephones/status/123').
      #   Used to derive a contact_type tag for the metric.
      # @return [Nil] Returns nil only if the passed transaction status is not a final status
      #
      def increment_transaction_results(response, bucket1 = 'posts_and_puts', path: nil)
        status = status_in(response)

        return unless final_status?(status)

        contact_type = contact_type_from_path(path)
        tags = build_tags(contact_type:, error_code: failure?(status) ? error_code_in(response) : nil)

        StatsD.increment("#{STATSD_KEY_PREFIX}.#{bucket1}.#{bucket_for(status)}", tags:)
      end

      # Reads the 'Source-App-Name' header and validates it against the middleware allowlist
      # to prevent unbounded StatsD tag cardinality.
      #
      # @return [String] an allowlisted source app name, or 'unknown' when unavailable/invalid
      def source_app
        raw = RequestStore.store.dig('additional_request_attributes', 'source')
        return UNKNOWN_SOURCE_APP if raw.blank?

        SourceAppMiddleware::SOURCE_APP_NAMES.include?(raw) ? raw : UNKNOWN_SOURCE_APP
      end

      # Increments the associated StatsD bucket with the passed in exception error key.
      #
      # @param key [String] A VAProfile exception key from the locales/exceptions file
      #   For example, 'VET360_ADDR133'.
      #
      def increment_exception(key)
        StatsD.increment("#{STATSD_KEY_PREFIX}.exceptions", tags: ["exception:#{key.downcase}"])
      end

      # Derives a contact_type tag from a request path. Handles write paths ('telephones')
      # and status paths ('telephones/status/123'); returns a KNOWN_CONTACT_TYPES value or nil.
      #
      # @param path [String, nil] the request path
      # @return [String, nil] one of KNOWN_CONTACT_TYPES ('address'/'email'/'telephone'), or nil
      #
      def contact_type_from_path(path)
        segment = path.to_s.split('/').first
        return unless segment

        KNOWN_CONTACT_TYPES.find { |type| segment.start_with?(type) }
      end

      private

      def status_in(response)
        response&.body&.dig('tx_status')&.upcase
      end

      def error_code_in(response)
        code = response&.body&.dig('tx_messages', 0, 'code')&.to_s&.strip
        return unless code.present? && code.match?(/\A[A-Za-z0-9_]{1,20}\z/)

        code
      end

      def final_status?(status)
        (status.present? && success?(status)) || failure?(status)
      end

      def success?(status)
        FINAL_SUCCESS.include? status
      end

      def failure?(status)
        FINAL_FAILURE.include? status
      end

      def bucket_for(status)
        if success?(status)
          'success'
        elsif failure?(status)
          'failure'
        end
      end

      def build_tags(contact_type:, error_code: nil)
        tags = ["source_app:#{source_app}"]
        tags << "contact_type:#{contact_type}" if contact_type
        tags << "error_code:#{error_code}" if error_code
        tags.presence
      end
    end
  end
end
