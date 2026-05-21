# frozen_string_literal: true

module VREClaimsEvidenceFolderHelpers
  private

  def claims_evidence_default_folder_identifier(va_file_number:, ssn:)
    va_file_number.present? ? "VETERAN:FILENUMBER:#{va_file_number}" : "VETERAN:SSN:#{ssn}"
  end

  def claims_evidence_folder_identifier(folder_identifier:, va_file_number:, ssn:, user:)
    claims_evidence_folder_identifiers(folder_identifier:, va_file_number:, ssn:).find do |candidate_folder_identifier|
      claims_evidence_folder_exists?(folder_identifier: candidate_folder_identifier, user:)
    end
  end

  def claims_evidence_folder_identifiers(folder_identifier:, va_file_number:, ssn:)
    [
      folder_identifier,
      ("VETERAN:SSN:#{ssn}" if ssn.present?),
      ("VETERAN:FILENUMBER:#{va_file_number}" if va_file_number.present?)
    ].compact.uniq
  end

  def claims_evidence_folder_exists?(folder_identifier:, user:)
    search_service = ClaimsEvidenceApi::Service::Search.new
    search_service.folder_identifier = folder_identifier
    search_service.find(filters: {})
    true
  rescue Common::Client::Errors::ClientError => e
    raise e unless claims_evidence_folder_missing_error?(e)

    Rails.logger.warn(
      'Claims Evidence API folder lookup failed for VRE claim',
      {
        user_uuid: user&.uuid,
        status: e.status,
        code: e.body&.dig('code')
      }
    )
    false
  end

  def claims_evidence_folder_missing_error?(error)
    error.status == 403 && error.body.is_a?(Hash) && error.body['code'] == 'VEFSERR40302'
  end
end
