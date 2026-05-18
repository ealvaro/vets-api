# frozen_string_literal: true

PowerOfAttorneyPolicy = Struct.new(:user, :power_of_attorney) do
  def access?
    unless user.loa3? && user.icn.present? && (user.participant_id.present? || user.edipi.present?)
      log_access_denied
      return false
    end

    true
  end

  private

  def log_access_denied
    Rails.logger.info('POA ACCESS DENIED',
                      loa_current: user.loa&.dig(:current),
                      loa3: user.loa3?,
                      icn_present: user.icn.present?,
                      participant_id_present: user.participant_id.present?,
                      edipi_present: user.edipi.present?)
  end
end
