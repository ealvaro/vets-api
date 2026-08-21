# frozen_string_literal: true

require 'claims_evidence_api/service/files'

module DigitalFormsApi
  # Reads a claim's already-filed dPDF back from Claims Evidence for the veteran-facing viewing path.
  #
  # The dPDF is rendered by fdf-dpdf-generator and filed to Claims Evidence / the eFolder at submission
  # time. This does NOT call the generator — it only fetches the finished document from Claims Evidence,
  # reusing the existing `claims_evidence_api` integration.
  class DpdfDownloader
    # Raised when the claim has no filed dPDF to serve yet (no Claims Evidence submission / file_uuid).
    class NotFiled < StandardError; end

    # @param claim [SavedClaim] the dependents child claim (686/674) whose filed dPDF to fetch
    def initialize(claim)
      @claim = claim
    end

    # Fetch the claim's filed dPDF from Claims Evidence.
    #
    # @return [String] the PDF document bytes
    # @raise [DpdfDownloader::NotFiled] if the claim has no filed document to serve
    def fetch
      raise NotFiled, "no filed dPDF for saved_claim #{@claim.id}" if file_uuid.blank?

      files = ClaimsEvidenceApi::Service::Files.new
      version = files.retrieve(file_uuid).body['currentVersionUuid']
      raise NotFiled, "no current version for file #{file_uuid}" if version.blank?

      files.download(file_uuid, version).body
    end

    private

    # The Claims Evidence file UUID of the claim's filed form-level dPDF.
    #
    # A claim can own several `claims_evidence_api_submissions` rows: the form dPDF row
    # (`persistent_attachment_id` nil) plus one per uploaded supporting document. The index on
    # `[saved_claim_id, persistent_attachment_id, form_id]` is not unique, so an unscoped lookup could
    # return a supporting-attachment row (wrong PDF) or a still-pending row (no file id yet). Scope to
    # the form row, require it to be filed (`file_uuid` — alias of `va_claim_id` — present), and order
    # for determinism.
    #
    # @return [String, nil] the file UUID, or nil when the form-level dPDF is not filed yet
    def file_uuid
      @file_uuid ||= ClaimsEvidenceApi::Submission
                     .where(saved_claim_id: @claim.id, persistent_attachment_id: nil)
                     .where.not(file_uuid: nil)
                     .order(created_at: :desc)
                     .first&.file_uuid
    end
  end
end
