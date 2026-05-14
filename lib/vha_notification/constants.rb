# frozen_string_literal: true

module VHANotification
  class Constants
    # StatsD Keys
    STATSD_KEY_PREFIX = 'api.vha_notification'
    STATSD_SEND_CONSENT_SUCCESS_KEY = "#{STATSD_KEY_PREFIX}.send_consent.success".freeze
    STATSD_SEND_CONSENT_FAIL_KEY = "#{STATSD_KEY_PREFIX}.send_consent.fail".freeze
    STATSD_SEND_CONSENT_TOTAL_KEY = "#{STATSD_KEY_PREFIX}.send_consent.total".freeze
    STATSD_GET_TOKEN_SUCCESS_KEY = "#{STATSD_KEY_PREFIX}.get_token.success".freeze
    STATSD_GET_TOKEN_FAIL_KEY = "#{STATSD_KEY_PREFIX}.get_token.fail".freeze

    # Error Messages
    TOKEN_RETRIEVAL_ERROR = 'Failed to retrieve VHA Notification API token'
    CONSENT_UPDATE_ERROR = 'Failed to update VHA consent and enrollment'
    INVALID_RESPONSE_ERROR = 'Invalid response from VHA Notification API'
  end
end
