# frozen_string_literal: true

MHVMessagingPolicy = Struct.new(:user, :mhv_messaging) do
  def access?
    unless user.mhv_correlation_id && user.va_patient?
      log_access_denied
      return false
    end

    return true if user.mhv_user_account&.sm_account_created == true

    log_access_denied
    false
  end

  def mobile_access?
    access?
  end

  private

  def denial_reason
    return 'no_mhv_correlation_id' unless user.mhv_correlation_id
    return 'not_va_patient' unless user.va_patient?
    return 'sm_account_not_created' unless user.mhv_user_account&.sm_account_created == true

    'unknown'
  end

  def log_access_denied
    Rails.logger.info(self.class::SM_ACCESS_LOG_MESSAGE,
                      denial_reason:,
                      mhv_account_nil: user.mhv_user_account.nil?,
                      mhv_account_patient: user.mhv_user_account&.patient,
                      va_patient: user.va_patient?,
                      sm_account_created: user.mhv_user_account&.sm_account_created,
                      user_uuid: user.uuid,
                      mhv_id: user.mhv_correlation_id.presence || 'false')
  end
end

MHVMessagingPolicy::SM_ACCESS_LOG_MESSAGE = 'SM ACCESS DENIED'
