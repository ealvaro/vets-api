# frozen_string_literal: true

module TravelClaim
  ##
  # Notification helpers for ClaimSubmissionService success and error emails.
  #
  module ClaimSubmissionNotificationService
    private

    ##
    # Sends a success notification if feature flag is enabled
    #
    def send_notification_if_enabled
      return unless Flipper.enabled?(:check_in_experience_travel_reimbursement)
      return if @check_in_uuid.blank?

      template_id = success_template_id
      claim_number_last_four = @claim_number_last_four

      log_notification('success', template_id:, claim_last_four: claim_number_last_four)

      CheckIn::TravelClaimNotificationJob.perform_async(
        @check_in_uuid,
        @appointment_date_yyyy_mm_dd,
        template_id,
        claim_number_last_four
      )
    end

    ##
    # Sends an error notification if feature flag is enabled
    #
    # @param error [Exception] the error that occurred
    #
    def send_error_notification_if_enabled(error)
      return unless Flipper.enabled?(:check_in_experience_travel_reimbursement)
      return if @check_in_uuid.blank?

      increment_metric_by_facility_type(
        CheckIn::Constants::CIE_STATSD_ERROR_NOTIFICATION,
        CheckIn::Constants::OH_STATSD_ERROR_NOTIFICATION
      )

      template_id = determine_error_template_id(error)
      claim_number_last_four = @claim_number_last_four || 'unknown'

      log_notification('error', template_id:, failed_step: @current_step || 'unknown',
                                error_class: error.class.name)

      CheckIn::TravelClaimNotificationJob.perform_async(
        @check_in_uuid,
        @appointment_date_yyyy_mm_dd,
        template_id,
        claim_number_last_four
      )
    end

    def log_notification(type, **extra)
      return unless Flipper.enabled?(:check_in_experience_travel_claim_logging)

      log_data = {
        message: "#{CheckIn::Constants::LOG_PREFIX}: Sending #{type} notification",
        check_in_uuid: @check_in_uuid,
        facility_type: @facility_type,
        correlation_id:
      }.merge(extra)

      Rails.logger.info(log_data)
    end

    ##
    # Returns the appropriate success template ID based on facility type
    #
    # @return [String] template ID for success notifications
    #
    def success_template_id
      if @facility_type&.downcase == 'oh'
        CheckIn::Constants::OH_SUCCESS_TEMPLATE_ID
      else
        CheckIn::Constants::CIE_SUCCESS_TEMPLATE_ID
      end
    end

    ##
    # Returns the appropriate error template ID based on facility type
    #
    # @return [String] template ID for error notifications
    #
    def error_template_id
      if @facility_type&.downcase == 'oh'
        CheckIn::Constants::OH_ERROR_TEMPLATE_ID
      else
        CheckIn::Constants::CIE_ERROR_TEMPLATE_ID
      end
    end

    ##
    # Determines the appropriate error template ID based on the error type
    #
    def determine_error_template_id(error)
      if error.is_a?(Common::Exceptions::BackendServiceException) && duplicate_claim_error?(error)
        @facility_type&.downcase == 'oh' ? CheckIn::Constants::OH_DUPLICATE_TEMPLATE_ID : CheckIn::Constants::CIE_DUPLICATE_TEMPLATE_ID
      else
        error_template_id
      end
    end
  end
end
