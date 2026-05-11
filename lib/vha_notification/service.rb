# frozen_string_literal: true

require 'common/client/base'
require 'vha_notification/configuration'
require 'vha_notification/constants'
require 'vha_notification/jwt_generator'

module VhaNotification
  class Service < Common::Client::Base
    configuration VhaNotification::Configuration
    STATSD_KEY_PREFIX = 'api.vha_notification'

    ##
    # Sends MST consent information to VHA Notification API
    #
    # @param [String] pid - Veteran's PID (Person ID)
    # @param [Boolean] consent_data - MST consent value (true/false)
    # @return [Hash] Success response or error details
    #
    def send_mst_consent(pid, consent_data)
      validate_pid(pid)
      validate_consent_data(consent_data)
      payload = build_consent_payload(pid, consent_data)

      bearer_token = get_bearer_token
      response = config.post_consent_update(pid, payload, bearer_token)

      log_success(response)
      StatsD.increment(Constants::STATSD_SEND_CONSENT_SUCCESS_KEY)

      { success: true, response: response.body }
    rescue VhaNotification::ServiceError
      StatsD.increment(Constants::STATSD_SEND_CONSENT_FAIL_KEY)
      raise
    rescue => e
      StatsD.increment(Constants::STATSD_SEND_CONSENT_FAIL_KEY)
      handle_error(e)
    ensure
      StatsD.increment(Constants::STATSD_SEND_CONSENT_TOTAL_KEY)
    end

    private

    ##
    # Generates bearer token for VHA Notification API
    #
    # @return [String] Bearer token
    #
    def get_bearer_token
      token = VhaNotification::JwtGenerator.encode_jwt
      StatsD.increment(Constants::STATSD_GET_TOKEN_SUCCESS_KEY)
      token
    rescue => e
      StatsD.increment(Constants::STATSD_GET_TOKEN_FAIL_KEY)
      ::Rails.logger.error(
        'VHA Notification: Failed to generate bearer token',
        { error: e.message, error_class: e.class.to_s }
      )
      raise VhaNotification::ServiceError, Constants::TOKEN_RETRIEVAL_ERROR
    end

    ##
    # Validates PID format
    #
    # @param [String] pid - Veteran's PID
    # @raise [VhaNotification::ServiceError] If PID is invalid
    #
    def validate_pid(pid)
      raise VhaNotification::ServiceError, 'PID is required' if pid.blank?
      raise VhaNotification::ServiceError, 'PID must be a string' unless pid.is_a?(String)
    end

    ##
    # Validates consent data value
    #
    # @param [Boolean] consent_data - Consent boolean value
    # @raise [VhaNotification::ServiceError] If consent data is invalid
    #
    def validate_consent_data(consent_data)
      raise VhaNotification::ServiceError, 'Consent data is required' if consent_data.nil?

      return if consent_data.is_a?(TrueClass) || consent_data.is_a?(FalseClass)

      raise VhaNotification::ServiceError, 'Consent data must be a boolean'
    end

    def build_consent_payload(pid, consent_data)
      {
        source:,
        vhaCommsConsent: consent_data,
        participantId: pid.to_i
      }
    end

    def source
      source_value = ActiveModel::Type::String.new.cast(Settings.vha_notification.source)&.strip
      return 'ibm' if source_value.blank? || source_value == '0'

      source_value
    end

    ##
    # Logs successful consent update
    #
    # @param [Faraday::Response] response - API response
    #
    def log_success(response)
      ::Rails.logger.info(
        'VHA Notification: MST consent successfully sent',
        { status: response.status, service: 'VhaNotification' }
      )
    end

    ##
    # Handles and logs errors from API calls
    #
    # @param [StandardError] error - The error that occurred
    # @raise [VhaNotification::ServiceError] Always re-raises as ServiceError
    #
    def handle_error(error)
      error_message = Constants::CONSENT_UPDATE_ERROR

      # Include HTTP status if available, but omit response body to prevent PII leakage
      if error.respond_to?(:response) && error.response.present?
        error_message = "#{error_message} - HTTP #{error.response[:status]}"
      end

      ::Rails.logger.error(
        'VHA Notification: Failed to send MST consent',
        {
          error: error.message,
          error_class: error.class.to_s,
          service: 'VhaNotification'
        }
      )

      raise VhaNotification::ServiceError, error_message
    end
  end

  ##
  # Custom exception for VHA Notification service errors
  #
  class ServiceError < StandardError; end
end
