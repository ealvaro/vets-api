# frozen_string_literal: true

# Authorization policy that determines whether a user may access MHV
# (My HealtheVet) medical records. Access is granted only to LOA3 users who
# have an associated MHV user account flagged as a patient. All denials are
# logged with contextual metadata to aid debugging and auditing.
#
# @!attribute user
#   @return [User] the user whose access is being evaluated
# @!attribute mhv_medical_records
#   @return [Object] the medical records resource being authorized
MHVMedicalRecordsPolicy = Struct.new(:user, :mhv_medical_records) do
  # Determines whether the user is authorized to access MHV medical records.
  #
  # Access requires the user to be LOA3 verified and to have an MHV user
  # account marked as a patient. Any denial is logged via {#log_access_denied}.
  #
  # @return [Boolean] true if the user may access medical records, otherwise false
  def access?
    unless user.loa3?
      log_access_denied(self.class::MR_ACCESS_LOG_MESSAGE, nil)
      return false
    end

    account = user.mhv_user_account
    return true if account&.patient

    log_access_denied(self.class::MR_ACCESS_LOG_MESSAGE, account)
    false
  end

  private

  # Derives a human-readable reason describing why access was denied.
  #
  # @param account [Object, nil] the user's MHV account, if any
  # @return [String] a short code describing the denial reason
  def denial_reason(account)
    return 'not_loa3' unless user.loa3?
    return "account_nil:#{user.mhv_user_account_error || 'none'}" if account.nil?
    return 'not_patient' unless account.patient

    'unknown'
  end

  # Logs an access-denied event with contextual metadata for debugging and auditing.
  #
  # @param message [String] the log message to emit
  # @param account [Object, nil] the user's MHV account, if any
  # @return [void]
  def log_access_denied(message, account)
    Rails.logger.info(message,
                      denial_reason: denial_reason(account),
                      mhv_account_nil: account.nil?,
                      mhv_account_patient: account&.patient,
                      loa3: user.loa3?,
                      icn: user.icn,
                      mhv_id: user.mhv_correlation_id.presence || 'false',
                      va_patient: user.va_patient?)
  end
end

# Log message emitted whenever medical records access is denied.
MHVMedicalRecordsPolicy::MR_ACCESS_LOG_MESSAGE = 'MR ACCESS DENIED'
