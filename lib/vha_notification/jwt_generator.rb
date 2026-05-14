# frozen_string_literal: true

require 'common/jwt_generator'

module VHANotification
  class JwtGenerator
    # static method
    # @see #encode_jwt
    def self.encode_jwt
      new.encode_jwt
    end

    # Returns a JWT token for use in Bearer auth
    def encode_jwt
      Common::JwtGenerator.encode_jwt(
        issuer:,
        private_key:,
        user_id:,
        station_id:,
        application_id:
      )
    end

    private

    # Issuer assigned
    def issuer
      required_string_setting(notification_settings&.issuer, 'Settings.vha_notification.issuer')
    end

    # VBMS user logged in to the application; if no user interaction needs to be a system user
    def user_id
      required_string_setting(notification_settings&.user_id, 'Settings.vha_notification.user_id')
    end

    # Station for above user
    def station_id
      required_string_setting(notification_settings&.station_id, 'Settings.vha_notification.station_id')
    end

    # retrieve the secret from settings
    def private_key
      required_string_setting(notification_settings&.jwt_secret, 'Settings.vha_notification.jwt_secret')
    end

    def application_id
      required_string_setting(notification_settings&.application_id, 'Settings.vha_notification.application_id')
    end

    def notification_settings
      Settings.vha_notification
    end

    def required_string_setting(value, setting_name)
      coerced_value = ActiveModel::Type::String.new.cast(value)&.strip
      return coerced_value if coerced_value.present?

      raise ArgumentError, "#{setting_name} must be present and coercible to a non-empty string"
    end
  end
end
