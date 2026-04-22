# frozen_string_literal: true

module Vass
  ##
  # Service class for sending OTP codes via VANotify.
  #
  # This service handles sending One-Time Passwords (OTP) to users via email
  # using VA Notify. Credentials must come from the dedicated VASS workspace
  # (`Settings.vanotify.services.vass`), not `va_gov`.
  #
  # @example Send OTP via email
  #   service = Vass::VANotifyService.build
  #   service.send_otp(
  #     contact_method: 'email',
  #     contact_value: 'veteran@example.com',
  #     otp_code: '123456'
  #   )
  #
  class VANotifyService
    attr_reader :notify_client, :api_key

    ##
    # Builds a VANotifyService instance.
    #
    # @param opts [Hash] Options to create the service
    # @option opts [String] :api_key VANotify API key (optional, defaults to dedicated VASS workspace key)
    #
    # @return [Vass::VANotifyService] An instance of this class
    #
    def self.build(opts = {})
      new(opts)
    end

    ##
    # Initializes a new VANotifyService.
    #
    # @param opts [Hash] Options to create the service
    # @option opts [String] :api_key VANotify API key (optional, defaults to dedicated VASS workspace key)
    #
    # @return [Vass::VANotifyService] An instance of this class
    #
    def initialize(opts = {})
      @api_key = vass_workspace_api_key(opts)
      # VaNotify::Service is the shared vets-api client for VA Notify; the workspace
      # (rate limits, templates) is determined entirely by @api_key from `vanotify.services.vass`.
      @notify_client = VaNotify::Service.new(@api_key)
    end

    ##
    # Sends an OTP code via email.
    #
    # @param contact_method [String] Contact method (must be 'email')
    # @param contact_value [String] Email address
    # @param otp_code [String] OTP code to send
    #
    # @return [VaNotify::NotificationResponse] Response from VANotify
    # @raise [ArgumentError] if contact_method is invalid
    # @raise [VANotify::Error] if VANotify service fails
    #
    def send_otp(contact_method:, contact_value:, otp_code:)
      raise ArgumentError, "Invalid contact_method: #{contact_method}. Must be 'email'" unless contact_method == 'email'

      send_email_otp(contact_value, otp_code)
    end

    private

    ##
    # Sends OTP via email.
    #
    # @param email_address [String] Email address
    # @param otp_code [String] OTP code
    #
    # @return [VaNotify::NotificationResponse] Response from VANotify
    #
    def send_email_otp(email_address, otp_code)
      notify_client.send_email(
        email_address:,
        template_id: email_template_id,
        personalisation: { otp_code: }
      )
    end

    ##
    # API key for the VASS VA Notify workspace (`Settings.vanotify.services.vass`).
    #
    # @return [String] API key
    #
    def vass_workspace_api_key(opts)
      opts[:api_key] || vass_notify_service_settings.api_key
    end

    ##
    # Returns the email template ID for OTP.
    #
    # @return [String] Template ID
    #
    def email_template_id
      vass_notify_service_settings.template_id.otp_email ||
        raise(ArgumentError, 'VASS OTP email template ID not configured')
    end

    def vass_notify_service_settings
      Settings.vanotify.services.vass
    end
  end
end
