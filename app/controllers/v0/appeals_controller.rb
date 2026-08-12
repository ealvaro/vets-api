# frozen_string_literal: true

require 'lighthouse/benefits_documents/constants'

module V0
  class AppealsController < AppealsBaseController
    service_tag 'appeal-status'

    def index
      appeals_response = appeals_service.get_appeals(current_user)
      body = appeals_response.body

      if Flipper.enabled?(:cst_supplemental_claims_evidence_upload, current_user)
        body = enrich_with_evidence_submissions(body)
      end

      render json: body
    end

    private

    def enrich_with_evidence_submissions(body)
      return body unless body.is_a?(Hash) && body['data'].present?

      sc_ids = body['data'].filter_map { |e| e['id'] if e['type'] == 'supplementalClaim' }
      return body if sc_ids.empty?

      grouped = EvidenceSubmission.where(
        user_account_id: current_user.user_account_uuid,
        caseflow_claim_id: sc_ids,
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS]
      ).group_by(&:caseflow_claim_id)

      enriched_data = body['data'].map do |entry|
        next entry unless entry['type'] == 'supplementalClaim'

        submissions = (grouped[entry['id']] || []).map { |es| serialize_evidence_submission(es) }
        attributes = entry['attributes'].is_a?(Hash) ? entry['attributes'] : {}
        attributes = attributes.merge('evidenceSubmissions' => submissions)
        entry.merge('attributes' => attributes)
      end

      body.merge('data' => enriched_data)
    end

    def serialize_evidence_submission(evidence_submission)
      metadata = parse_template_metadata(evidence_submission.template_metadata)
      {
        'id' => evidence_submission.id.to_s,
        'fileName' => metadata.dig('personalisation', 'file_name'),
        'documentType' => metadata.dig('personalisation', 'document_type'),
        'uploadStatus' => evidence_submission.upload_status,
        'createdAt' => evidence_submission.created_at.iso8601
      }
    end

    def parse_template_metadata(raw)
      return {} if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError, TypeError
      {}
    end
  end
end
