# frozen_string_literal: true

require 'rx/client'

MHVPrescriptionsPolicy = Struct.new(:user, :mhv_prescriptions) do
  def access?
    unless user.loa3?
      log_access_denied(self.class::RX_ACCESS_LOG_MESSAGE, nil)
      return false
    end

    account = user.mhv_user_account
    return true if account&.patient || account&.champ_va

    log_access_denied(self.class::RX_ACCESS_LOG_MESSAGE, account)
    false
  end

  private

  def denial_reason(account)
    return 'not_loa3' unless user.loa3?
    return "account_nil:#{user.mhv_user_account_error || 'none'}" if account.nil?
    return 'not_patient_or_champ_va' if !account.patient && !account.champ_va

    'unknown'
  end

  def log_access_denied(message, account)
    Rails.logger.info(message,
                      denial_reason: denial_reason(account),
                      mhv_account_nil: account.nil?,
                      mhv_account_patient: account&.patient,
                      mhv_account_champ_va: account&.champ_va,
                      loa3: user.loa3?,
                      icn: user.icn,
                      mhv_id: user.mhv_correlation_id.presence || 'false',
                      sign_in_service: user.identity.sign_in[:service_name],
                      va_facilities: user.va_treatment_facility_ids.length,
                      va_patient: user.va_patient?)
  end
end

MHVPrescriptionsPolicy::RX_ACCESS_LOG_MESSAGE = 'RX ACCESS DENIED'
