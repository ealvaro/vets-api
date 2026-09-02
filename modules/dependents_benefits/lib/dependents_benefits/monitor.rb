# frozen_string_literal: true

require 'logging/base_monitor'

module DependentsBenefits
  ##
  # Monitor class for tracking claim submission events
  #
  # This class provides methods for tracking various events during the dependents_benefits claim
  # submission process, including successes, failures, and retries.
  #
  # @example Tracking a submission success
  #   monitor = DependentsBenefits::Monitor.new
  #   monitor.track_submission_success(claim, service, user_uuid)
  #
  class Monitor < ::Logging::BaseMonitor
    # statsd key for api
    CLAIM_STATS_KEY = 'api.dependents_benefits'
    # statsd key for sidekiq
    SUBMISSION_STATS_KEY = 'worker.lighthouse.dependents_benefits_intake_job'
    # statsd key for generic module events
    MODULE_STATS_KEY = 'module.dependents_benefits'
    # statsd key for pension-related submissions
    PENSION_SUBMISSION_STATS_KEY = 'dependents_benefits.pension_submission'
    # statsd key for no SSN claims
    NO_SSN_SUBMISSION_STATS_KEY = 'dependents_benefits.no_ssn_claims'

    # Allowed context keys for logging
    ALLOWLIST = %w[
      claim_id
      claim_label
      confirmation_number
      error
      form_id
      form_type
      parent_claim_id
      proc_id
      response
      saved_claim_id
      submission_id
      tags
      non_blank_dlvs
      messages
      severity
      text
      http_status
      key
      timestamp
    ].freeze

    # @param claim_id [Integer, nil] optional SavedClaim id used to inspect claim for tags
    # @param user [Object, nil] optional user used for flipper checks
    def initialize(claim_id = nil, user = nil)
      @claim_id = claim_id
      @claim = find_claim(claim_id)
      @user = user

      super(service_name, allowlist: ALLOWLIST, safe_keys: %w[parent_claim_id])

      @use_v3 = get_use_v3
      @use_v3_removal = get_use_v3_removal(@claim)
      @tags = get_tags
    end

    ##
    # Checks if v3 logging is enabled
    # @return [Boolean] true if v3 logging is enabled, false otherwise
    def v3_logging_enabled?
      @v3_logging_enabled ||= Flipper.enabled?(:dependents_v3_removal_picklist_logging)
    end

    ##
    # Tracks a generic error event
    # Provides a general-purpose error tracking method that can be used
    # across different components with appropriate tagging
    #
    # @param message [String] Error message to log
    # @param action [String] Action being performed when error occurred
    # @param component [String, nil] Optional component name for tagging
    # @param context [Hash] Additional context data
    # @return [void]
    def track_error_event(message, action:, component: nil, **context)
      tags = { action: }
      tags[:component] = component if component
      context = append_tags(context, **tags)
      submit_event(:error, message, module_stats_key, **context)
    end

    ##
    # Tracks a generic info event
    # Provides a general-purpose info tracking method that can be used
    # across different components with appropriate tagging
    #
    # @param message [String] Info message to log
    # @param action [String] Action being performed
    # @param component [String, nil] Optional component name for tagging
    # @param context [Hash] Additional context data
    # @return [void]
    def track_info_event(message, action:, component: nil, **context)
      tags = { action: }
      tags[:component] = component if component
      context = append_tags(context, **tags)
      stats_key = context[:module_stats_key] || module_stats_key
      context.delete(:module_stats_key)
      submit_event(:info, message, stats_key, **context)
    end

    ##
    # Tracks a generic warning event
    # Provides a general-purpose warning tracking method that can be used
    # across different components with appropriate tagging
    #
    # @param message [String] Warning message to log
    # @param action [String] Action being performed
    # @param component [String, nil] Optional component name for tagging
    # @param context [Hash] Additional context data
    # @return [void]
    def track_warning_event(message, action:, component: nil, **context)
      tags = { action: }
      tags[:component] = component if component
      context = append_tags(context, **tags)
      submit_event(:warn, message, module_stats_key, **context)
    end

    private

    # @see Logging::BaseMonitor#submit_event
    def submit_event(level, message, stats_key, **context)
      context[:call_location] ||= caller_locations.second # the caller to the `track_*_event` method
      super(level, message, stats_key, **context)
    end

    ##
    # Module application name used for logging
    # @return [String]
    def service_name
      'dependents-benefits-application'
    end

    ##
    # Append tags to the context being logged
    #
    # @param context [Hash] the context being passed to the logger
    # @param tags [Mixed] the list of tags to be appended - key:value
    def append_tags(context, **tags)
      context[:tags] ||= []
      # Include monitor's base tags (service, use_v3, v3_removal, etc...)
      context[:tags] += @tags if @tags.present?
      # Add any additional tags passed in
      tags.each { |k, v| context[:tags] += ["#{k}:#{v}"] }
      context[:tags].uniq!
      context
    end

    ##
    # Stats key for DD
    # @return [String]
    def claim_stats_key
      CLAIM_STATS_KEY
    end

    ##
    # Stats key for Sidekiq DD logging
    # @return [String]
    def submission_stats_key
      SUBMISSION_STATS_KEY
    end

    ##
    # Stats key for generic module events
    # @return [String]
    def module_stats_key
      MODULE_STATS_KEY
    end

    ##
    # Class name for log messages
    # @return [String]
    def name
      self.class.name
    end

    ##
    # Form ID for the dependents_benefits application
    # @return [String]
    def form_id
      DependentsBenefits::FORM_ID
    end

    ##
    # Load a saved claim for inspection
    # @param claim_id [Integer] the id of the claim to load
    # @return [SavedClaim, nil] the loaded claim or nil if not found
    def find_claim(claim_id)
      return nil if claim_id.nil?

      ::SavedClaim.find(claim_id)
    rescue => e
      Rails.logger.warn('Unable to find claim for DependentsBenefits::Monitor', claim_id:, error: e)
      nil
    end

    ##
    # tag used for logging to identify ALL claims with v3 flipper active
    # @return [Boolean] whether the v3 flipper is enabled for the user
    def get_use_v3
      return false unless v3_logging_enabled?
      return false if @user.nil?

      actor = actor_for_flipper(@user)
      Flipper.enabled?(:va_dependents_v3, actor)
    end

    ##
    # Normalize a user-like object into something Flipper can accept as an actor (based on User#flipper_id)
    # This can either be current_user from the claims controller or what's
    #
    # @param user [Object] the user-like object to normalize
    # @return [Object] the normalized actor for Flipper checks
    def actor_for_flipper(user)
      return user if user.respond_to?(:flipper_id)

      OpenStruct.new(flipper_id: user.uuid)
    end

    ##
    # tag used for logging to identify claims with v3 removal flow active
    # @param claim [SavedClaim] the claim to inspect for v3 removal flow
    # @return [Boolean] whether the claim is part of the v3 removal flow
    def get_use_v3_removal(claim)
      return false unless v3_logging_enabled?
      return false if claim.nil?

      parsed_form = claim.parsed_form

      return false if parsed_form.nil? # this should not happen

      parsed = parsed_form.try(:with_indifferent_access) || parsed_form

      !!parsed['is_v3_removal_flow']
    end

    ##
    # Generate tags for logging based on flipper states and claim attributes
    # @return [Array<String>] the list of tags to be included in logs
    def get_tags
      additional_tags = @tags.dup || []
      additional_tags << "service:#{service}"
      if v3_logging_enabled?
        # if user is nil, but claim dta has is_v3_removal_flow true, we know that feature flag is ON
        additional_tags << "use_v3:#{@use_v3 || @use_v3_removal}" if @user.present? || @use_v3_removal
        additional_tags << "v3_removal:#{@use_v3_removal}" if @claim.present?
      end
      additional_tags
    end
  end
end
