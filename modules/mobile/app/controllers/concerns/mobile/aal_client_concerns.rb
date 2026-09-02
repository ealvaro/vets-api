# frozen_string_literal: true

require 'mhv/aal/client'

module Mobile
  ##
  # Server-side AAL (Account Activity Log) logging for medical record access from the
  # VA: Health and Benefits mobile app.
  #
  # By design the public method here is non-blocking: it never raises, so a failure to log
  # an AAL entry cannot affect the primary API response. All logging is gated behind the
  # +:mhv_mobile_medical_records_aal_logging+ feature flag and is deduplicated once per
  # session via the shared AAL client.
  #
  # Entries are logged via +AAL::MobileClient+, which authenticates using the mobile
  # app's own MHV app registration (app id 102, ticket #147838 AC #7). This lets MHV
  # distinguish mobile-originated entries from web on its own, so no platform flag needs
  # to be written into the AAL payload itself.
  #
  module AALClientConcerns
    extend ActiveSupport::Concern

    ##
    # Centralized registry of AAL activity type strings used by mobile medical records
    # controllers. Values must match the web implementation so MHV can correlate activity
    # across platforms.
    #
    module ActivityTypes
      ALLERGY_AND_REACTIONS = 'Allergy and Reactions'
      VACCINES = 'Vaccines'
      LAB_AND_TEST_RESULTS = 'Lab and test results'
    end

    ##
    # Log a "View" AAL entry for a medical record domain. Non-blocking: any error (including
    # a missing MHV session or client failure) is logged and swallowed so the request
    # continues normally.
    #
    # @param activity_type [String] the AAL activity type, one of the +ActivityTypes+ constants
    # @param action [String] the AAL action, defaults to 'View'
    #
    def log_mhv_aal(activity_type, action: 'View')
      return unless Flipper.enabled?(:mhv_mobile_medical_records_aal_logging, current_user)
      return if current_user&.mhv_correlation_id.blank?

      aal_client.authenticate
      aal_client.create_aal(aal_attributes(activity_type, action), true, current_user&.last_signed_in)
    rescue => e
      Rails.logger.error('Mobile MHV AAL logging failed', exception: e)
      nil
    end

    private

    def aal_attributes(activity_type, action)
      { activity_type:, action:, performer_type: 'Self', status: 1 }
    end

    def aal_client
      @aal_client ||= AAL::MobileClient.new(session: { user_id: current_user&.mhv_correlation_id })
    end
  end
end
