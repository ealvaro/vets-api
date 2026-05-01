# frozen_string_literal: true

MHVMedicalRecordsPolicy = Struct.new(:user, :mhv_medical_records) do
  MR_ACCOUNT_TYPES = %w[Premium].freeze
  MR_ACCESS_LOG_MESSAGE = 'MR ACCESS DENIED'

  def access?
    if Flipper.enabled?(:mhv_medical_records_new_eligibility_check)
      unless user.loa3?
        log_access_denied(MR_ACCESS_LOG_MESSAGE, nil)
        return false
      end

      account = user.mhv_user_account
      return true if account&.patient

      log_access_denied(MR_ACCESS_LOG_MESSAGE, account)
      false
    else
      MR_ACCOUNT_TYPES.include?(user.mhv_account_type) && user.va_patient?
    end
  end

  private

  def denial_reason(account)
    return 'not_loa3' unless user.loa3?
    return "account_nil:#{user.mhv_user_account_error || 'none'}" if account.nil?
    return 'not_patient' unless account.patient

    'unknown'
  end

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
