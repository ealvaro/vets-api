# frozen_string_literal: true

require 'logging/monitor'

module DigitalFormsApi
  # Monitor for Digital Forms API
  class Monitor < Logging::Monitor
    # create a monitor
    #
    # @param allowlist [Array<String>] list of allowed params
    def initialize(allowlist = [])
      super('digital-forms-api', allowlist:)
    end

    # utility function, @see Rails.logger
    #
    # @param msg [Mixed] the message to be logged
    #
    # @return [String] the formatted message, preceded with the monitor class name
    def format_message(msg)
      format('%<class>s: %<msg>s', { class: self.class.name, msg: msg.to_s })
    end

    # utility function to format metric tags for DataDog
    #
    # @param tag_hash [Hash] key-value pairs for metric tags
    #
    # @return [Array<String>] an array of string; eg. ["key:value" ...]
    def format_tags(tag_hash)
      tag_hash.map { |key, value| "#{key}:#{value}" }
    end

    # Monitor to be used within Service classes
    class Service < Monitor
      # StatsD metric for service-level API requests
      METRIC = 'module.digital_forms_api.service.request'
      # StatsD metric for template cache hit/miss events
      TEMPLATE_CACHE_METRIC = 'module.digital_forms_api.templates.cache'
      # StatsD metric for total template fetch attempts
      TEMPLATE_FETCH_METRIC = 'module.digital_forms_api.templates.fetch'
      # StatsD metric for schema cache hit/miss events
      SCHEMA_CACHE_METRIC = 'module.digital_forms_api.schemas.cache'
      # StatsD metric for total schema fetch attempts
      SCHEMA_FETCH_METRIC = 'module.digital_forms_api.schemas.fetch'
      # allowed logging params
      ALLOWLIST = %w[
        cache_status
        claim_label
        code
        duration
        endpoint
        ep_code
        error
        form_id
        submission_id
        document_id
        method
        reason
      ].freeze

      def initialize
        super(ALLOWLIST)
      end

      # track the api request performed and the response/error
      # @see Common::Client::Base#perform
      # @see Common::Client::Errors::ClientError
      #
      # @param method [String|Symbol] eg. get, post, put
      # @param endpoint [String] the requested service endpoint
      # @param code [Integer|String] the response code
      # @param reason [String] the response `reason_phrase` or the error message
      # @param duration [Integer] the duration of the request in milliseconds
      # @param call_location [Logging::CallLocation|Thread::Backtrace::Location] calling point to be logged
      def track_api_request(method, endpoint, code, reason, duration, call_location: nil, **context) # rubocop:disable Metrics/ParameterLists
        call_location ||= caller_locations.first

        message = format_message("#{code} #{reason}")
        tags = { method:, code:, endpoint: }.merge(context[:tags] || {})
        context = { method:, code:, endpoint:, reason:, duration: }.merge(context)
        context.delete(:tags) # avoid overwriting the tags arg to `track_request`

        level = /^2\d\d$/.match?(code.to_s.strip) ? :info : :error

        StatsD.measure("#{METRIC}.duration", duration, tags:)
        track_request(level, message, METRIC, call_location:, tags: format_tags(tags), **context)
      end

      # track cache status when resolving a form template
      def track_template_cache(form_id, cache_status, call_location: nil)
        call_location ||= caller_locations.first

        tags = { endpoint: 'templates', form_id:, cache_status: }
        message = format_message("template cache #{cache_status}")
        context = { endpoint: 'templates', form_id:, cache_status: }

        # Total template fetch attempt volume by form
        StatsD.increment(TEMPLATE_FETCH_METRIC, tags:)
        # Cache hit/miss ratio and event details
        track_request(:info, message, TEMPLATE_CACHE_METRIC, call_location:, tags: format_tags(tags), **context)
      end

      # track cache status when resolving a form schema
      def track_schema_cache(form_id, cache_status, call_location: nil)
        call_location ||= caller_locations.first

        tags = { endpoint: 'schemas', form_id:, cache_status: }
        message = format_message("schema cache #{cache_status}")
        context = { endpoint: 'schemas', form_id:, cache_status: }

        # Total schema fetch attempt volume by form
        StatsD.increment(SCHEMA_FETCH_METRIC, tags:)
        # Cache hit/miss ratio and event details
        track_request(:info, message, SCHEMA_CACHE_METRIC, call_location:, tags: format_tags(tags), **context)
      end
    end

    # Monitor to be used within Controllers
    class Controller < Monitor
      # StatsD metric for submissions#show controller events
      SHOW_METRIC = 'module.digital_forms_api.submissions.show'
      # StatsD metric for template version tracking events
      TEMPLATE_VERSION_METRIC = 'module.digital_forms_api.submissions.template_version'

      # Allowed logging params for controller monitor events
      ALLOWLIST = %w[
        auth_denial_reason
        duration_ms
        endpoint
        error
        error_class
        error_source
        failure_stage
        feature_flag_enabled
        form_id
        http_status
        submission_id
        template_version
        upstream_reason
        upstream_status
      ].freeze

      def initialize
        super(ALLOWLIST)
      end

      # Track a submissions#show controller event with status, tags, and optional duration metric
      #
      # @param http_status [Integer] the HTTP response status code
      # @param submission_id [String] the submission identifier
      # @param form_id [String] the form identifier
      # @param call_location [Logging::CallLocation, Thread::Backtrace::Location, nil] the caller location
      # @param context [Hash] additional context (template_version, error_class, failure_stage, duration_ms, etc.)
      def track_show(http_status:, submission_id:, form_id:, call_location: nil, **context)
        call_location ||= caller_locations.first

        tags = { endpoint: 'submissions_show', http_status:, form_id: }
        tags[:template_version] = context[:template_version] if context[:template_version].present?
        tags[:error_class] = context[:error_class] if context[:error_class].present?
        tags[:failure_stage] = context[:failure_stage] if context[:failure_stage].present?
        tags[:error_source] = context[:error_source] if context[:error_source].present?
        tags[:auth_denial_reason] = context[:auth_denial_reason] if context[:auth_denial_reason].present?
        tags[:feature_flag_enabled] = context[:feature_flag_enabled] unless context[:feature_flag_enabled].nil?

        level = /^2\d\d$/.match?(http_status.to_s.strip) ? :info : :error
        message = format_message("submissions#show #{http_status}")
        payload = { endpoint: 'submissions_show', http_status:, submission_id:, form_id: }.merge(context)

        StatsD.measure("#{SHOW_METRIC}.duration", context[:duration_ms], tags:) if context[:duration_ms].present?

        track_request(level, message, SHOW_METRIC, call_location:, tags: format_tags(tags), **payload)
      end

      # Track the template version used for a submissions#show response
      #
      # @param form_id [String] the form identifier
      # @param template_version [String] the version of the template retrieved
      # @param call_location [Logging::CallLocation, Thread::Backtrace::Location, nil] the caller location
      def track_template_version(form_id:, template_version:, call_location: nil)
        call_location ||= caller_locations.first
        return if template_version.blank?

        tags = { endpoint: 'submissions_show', form_id:, template_version: }
        message = format_message("template version #{template_version}")
        payload = { endpoint: 'submissions_show', form_id:, template_version: }

        track_request(:info, message, TEMPLATE_VERSION_METRIC, call_location:, tags: format_tags(tags), **payload)
      end
    end
  end
end
