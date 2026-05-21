# frozen_string_literal: true

module VREClaimsEvidenceUpload
  include VREClaimsEvidenceFolderHelpers

  private

  def upload_to_claims_evidence_api(form_path:, va_file_number:, ssn:, user:, doc_type:)
    upload_context, default_folder_identifier, resolved_folder_identifier =
      claims_evidence_upload_context(form_path:, va_file_number:, ssn:, user:, doc_type:)

    unless resolved_folder_identifier
      fallback_to_legacy_vbms_from_claims_evidence(
        context: upload_context,
        folder_identifier: default_folder_identifier,
        user:
      )
      return
    end

    upload_via_claims_evidence(
      resolved_folder_identifier:,
      user:,
      form_path:,
      doc_type:
    )
  end

  def claims_evidence_upload_context(form_path:, va_file_number:, ssn:, user:, doc_type:)
    upload_context = { form_path:, va_file_number:, ssn:, user:, doc_type: }
    default_folder_identifier = claims_evidence_default_folder_identifier(va_file_number:, ssn:)
    resolved_folder_identifier = resolve_claims_evidence_folder_identifier(
      upload_context:,
      folder_identifier: default_folder_identifier
    )
    [upload_context, default_folder_identifier, resolved_folder_identifier]
  end

  def resolve_claims_evidence_folder_identifier(upload_context:, folder_identifier:)
    claims_evidence_folder_identifier(
      folder_identifier:,
      va_file_number: upload_context[:va_file_number],
      ssn: upload_context[:ssn],
      user: upload_context[:user]
    )
  end

  def upload_via_claims_evidence(resolved_folder_identifier:, user:, form_path:, doc_type:)
    ce_uploader = ClaimsEvidenceApi::Uploader.new(resolved_folder_identifier)
    log_to_statsd('claims_evidence_api') do
      Rails.logger.info('Uploading VRE claim via Claims Evidence API', { user_uuid: user&.uuid })
      file_uuid = ce_uploader.upload_evidence(
        id,
        file_path: Rails.root.join(form_path).to_s,
        form_id: '28-1900',
        doctype: claims_evidence_document_type(doc_type)
      )
      persist_document_id(file_uuid)
    end
  end

  def claims_evidence_document_type(doc_type)
    doc_type.to_i.positive? ? doc_type.to_i : 1167
  end

  def fallback_to_legacy_vbms_from_claims_evidence(context:, folder_identifier:, user:)
    attempted_folder_identifier_count = claims_evidence_folder_identifiers(
      folder_identifier:,
      va_file_number: context[:va_file_number],
      ssn: context[:ssn]
    ).size
    Rails.logger.warn(
      'Claims Evidence API folder not found for VRE claim, falling back to legacy VBMS',
      {
        user_uuid: user&.uuid,
        attempted_folder_identifier_count:
      }
    )
    upload_to_legacy_vbms(**context)
  end
end
