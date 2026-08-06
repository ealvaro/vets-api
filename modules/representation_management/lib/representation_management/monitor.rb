# frozen_string_literal: true

require 'logging/base_monitor'

module RepresentationManagement
  # Monitor class for tracking representation management actions.
  class Monitor < ::Logging::BaseMonitor
    CLAIM_STATS_KEY = 'api.representation_management'
    SUBMISSION_STATS_KEY = 'worker.lighthouse.representation_management.submission'
    MODULE_STATS_KEY = 'module.representation_management'
    VALIDATION_ERROR_STATS_KEY = 'representation_management.validation_error'

    ALLOWLIST = %w[
      tags
    ].freeze

    def initialize
      super(service_name, allowlist: ALLOWLIST)

      @tags = []
    end

    # Logs one metric per normalized validation error type so Datadog can group by
    # controller/action and compare backend validation failures with frontend behavior.
    def track_validation_errors(message:, **context)
      # errors will be in the form of { field_name: ["error message"] }
      base_event_context = context.dup

      base_tags = context.except(:call_location, :errors, :tags).compact

      normalized_error_type_details(context[:errors]).each do |error_type, fields|
        event_context = base_event_context.dup
        event_context[:tags] = Array(base_event_context[:tags]).dup
        tags = base_tags.merge(validation_error_type: error_type)
        event_context[:tags] += fields.map { |field| "validation_error_field:#{field}" }
        event_context = append_tags_to_context(event_context, **tags)

        submit_event(:error, message, VALIDATION_ERROR_STATS_KEY, **event_context)
      end
    end

    private

    def service_name
      'representation_management'
    end

    def claim_stats_key
      # parent class will raise error if this isn't defined, but not used
      CLAIM_STATS_KEY
    end

    def submission_stats_key
      # parent class will raise error if this isn't defined, but not used
      SUBMISSION_STATS_KEY
    end

    def module_stats_key
      # parent class will raise error if this isn't defined, but not used
      MODULE_STATS_KEY
    end

    def name
      # parent class will raise error if this isn't defined, but not used
      self.class.name
    end

    def form_id
      # parent class will raise error if this isn't defined
      # form id gets set in each tracking method since can be 21-22 or 21-22a
      RepresentationManagement::FORM_ID
    end

    def append_tags_to_context(context, **tags)
      context_tags = context[:tags] ||= []
      context_tags += @tags if @tags.present?
      tags.each { |k, v| context_tags += ["#{k}:#{v}"] }
      context_tags.uniq!
      context[:tags] = context_tags
      context
    end

    def submit_event(level, message, stats_key, **context)
      context[:call_location] ||= caller_locations.second
      super(level, message, stats_key, **context)
    end

    def normalized_error_type_details(errors)
      # Collapse raw ActiveModel errors into one entry per normalized error type,
      # while retaining the field names that produced that type so they can be
      # emitted as Datadog tags on the same event.
      # Example:
      #   { veteran_first_name: ["can't be blank"], veteran_last_name: ["can't be blank"] }
      # becomes:
      #   { 'required_field_missing' => ['veteran_first_name', 'veteran_last_name'] }
      details = Hash.new { |hash, key| hash[key] = [] }

      errors.each do |field, field_errors|
        field_errors.each do |error_message|
          error_type = classify_error_type(error_message)
          details[error_type] << field.to_s
        end
      end

      return { 'unknown_validation_error' => [] } if details.empty?

      # Deduplicate fields so repeated messages on the same field only produce
      # one validation_error_field tag per normalized error type.
      details.transform_values(&:uniq)
    end

    def classify_error_type(error_message)
      text = error_message.to_s.downcase

      return 'required_field_missing' if text.include?("can't be blank")
      return 'length_too_long' if text.include?('too long')
      return 'length_too_short' if text.include?('too short')
      return 'length_wrong' if text.include?('wrong length')
      return 'format_invalid' if text.include?('is invalid')
      return 'lookup_not_found' if text.include?('not found')
      return 'invalid_consent_limit' if text.include?('is not a valid limitation of consent')

      'unknown_validation_error'
    end
  end
end
