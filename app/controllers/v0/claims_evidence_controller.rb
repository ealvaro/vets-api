# frozen_string_literal: true

require 'claims_evidence_api/service/files'
require 'logging/helper/data_scrubber'

module V0
  class ClaimsEvidenceController < ApplicationController
    service_tag 'claims-evidence'
    before_action :check_feature_enabled
    before_action { authorize :claims_evidence, :access? }

    MAX_FILE_SIZE = 99.megabytes
    ALLOWED_EXTENSIONS = %w[bmp jpeg jpg pdf png tif tiff txt].freeze

    def create
      # Separate locals, not one struct: if a later parse fails, the failure log still
      # has whatever the earlier ones established.
      uploaded_file = parse_uploaded_file
      doc_type_id = parse_document_type_id
      sc_id = parse_supplemental_claim_id

      result = ClaimsEvidence::UploadEvidence.new(
        current_user: @current_user,
        upload: build_upload_request(uploaded_file, doc_type_id, sc_id),
        password: params[:password]
      ).call

      render json: result.payload, status: result.status
    rescue ClaimsEvidenceApi::Service::Files::VirusFound => e
      log_upload_failure(e, uploaded_file, doc_type_id, sc_id)
      raise Common::Exceptions::UnprocessableEntity.new(detail: 'DOC_UPLOAD_SCAN_FAILED', source: self.class.name)
    rescue ClaimsEvidence::UploadEvidence::DuplicateUpload
      # Translate the internal signal into the response; unhandled it would render a 500.
      raise Common::Exceptions::UnprocessableEntity.new(detail: 'DOC_UPLOAD_DUPLICATE', source: self.class.name)
    rescue ClaimsEvidence::PdfUnlocker::Rejected => e
      raise_validation_failure(e.reason, e.code)
    rescue => e
      log_upload_failure(e, uploaded_file, doc_type_id, sc_id)
      raise
    end

    private

    # file_size is measured before decryption and has to stay that way: it keys the duplicate
    # check, and HexaPDF's rewrite is a different size, so a retry of the same locked PDF
    # would stop matching the row the first attempt left behind.
    def build_upload_request(uploaded_file, doc_type_id, sc_id)
      ClaimsEvidence::UploadRequest.new(
        file: uploaded_file,
        doc_type_id:,
        sc_id:,
        file_name: File.basename(uploaded_file.original_filename.to_s),
        file_size: uploaded_file.tempfile.size
      )
    end

    def raise_validation_failure(reason, code)
      increment_validation_failure(reason)
      raise Common::Exceptions::UnprocessableEntity.new(detail: code, source: self.class.name), cause: nil
    end

    def parse_uploaded_file
      uploaded_file = params[:file]
      if uploaded_file.blank?
        increment_validation_failure('missing_file')
        raise Common::Exceptions::ParameterMissing, 'file'
      end

      unless uploaded_file.class.name.include?('UploadedFile')
        increment_validation_failure('invalid_file')
        raise Common::Exceptions::InvalidFieldValue.new('file', uploaded_file.class.name)
      end

      validate_file_size(uploaded_file)
      validate_file_type(uploaded_file)
      uploaded_file
    end

    # Checked before the file is staged to disk or streamed upstream. An empty file would
    # otherwise reach the eFolder as a document nobody can open.
    def validate_file_size(uploaded_file)
      raise_validation_failure('empty_file', 'DOC_UPLOAD_EMPTY_FILE') if uploaded_file.size.zero?
      raise_validation_failure('file_too_large', 'DOC_UPLOAD_FILE_TOO_LARGE') if uploaded_file.size > MAX_FILE_SIZE
    end

    def validate_file_type(uploaded_file)
      extension = File.extname(uploaded_file.original_filename.to_s).delete_prefix('.').downcase
      return if ALLOWED_EXTENSIONS.include?(extension)

      raise_validation_failure('unsupported_file_type', 'DOC_UPLOAD_UNSUPPORTED_TYPE')
    end

    def parse_document_type_id
      doc_type_id_param = begin
        params.require(:documentTypeId)
      rescue ActionController::ParameterMissing
        increment_validation_failure('missing_document_type_id')
        raise
      end

      doc_type_id = begin
        Integer(doc_type_id_param)
      rescue ArgumentError, TypeError
        raise_validation_failure('malformed_document_type_id', 'DOC_UPLOAD_INVALID_DOC_TYPE_ID')
      end

      unless ClaimsEvidence::DocumentType.supported?(doc_type_id)
        raise_validation_failure('unsupported_document_type_id', 'DOC_UPLOAD_UNSUPPORTED_DOC_TYPE_ID')
      end

      doc_type_id
    end

    def parse_supplemental_claim_id
      sc_id = params[:supplementalClaimId].presence
      raise_validation_failure('missing_supplemental_claim_id', 'DOC_UPLOAD_MISSING_CLAIM_ID') unless sc_id

      sc_id = sc_id.to_s
      unless sc_id.match?(/\ASC\d+\z/)
        raise_validation_failure('malformed_supplemental_claim_id', 'DOC_UPLOAD_INVALID_CLAIM_ID')
      end

      sc_id
    end

    def log_upload_failure(error, uploaded_file, doc_type_id, sc_id)
      is_uploaded_file = uploaded_file&.class&.name&.include?('UploadedFile')
      document_type_id_for_log = doc_type_id || begin
        Integer(params[:documentTypeId])
      rescue ArgumentError, TypeError
        nil
      end

      Rails.logger.error(
        'ClaimsEvidenceController#create upload failed',
        document_type_id: document_type_id_for_log,
        supplemental_claim_id: sc_id,
        file_size: (is_uploaded_file ? uploaded_file.size : nil),
        content_type: (is_uploaded_file ? uploaded_file.content_type : nil),
        error: Logging::Helper::DataScrubber.scrub(error.message)
      )
    end

    def increment_validation_failure(reason)
      ClaimsEvidence::Metrics.increment('validation.failure', reason:)
    end

    def check_feature_enabled
      routing_error unless Flipper.enabled?(:cst_supplemental_claims_evidence_upload, @current_user)
    end
  end
end
