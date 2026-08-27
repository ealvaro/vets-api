# frozen_string_literal: true

require 'claims_evidence_api/service/files'
require 'claims_evidence_api/folder_identifier'
require 'lighthouse/benefits_documents/constants'
require 'logging/helper/data_scrubber'

module V0
  class ClaimsEvidenceController < ApplicationController
    service_tag 'claims-evidence'
    before_action :check_feature_enabled
    before_action { authorize :claims_evidence, :access? }

    STATSD_METRIC_PREFIX = ClaimsEvidence::Metrics::PREFIX
    STATSD_TAGS = ClaimsEvidence::Metrics::TAGS
    MAX_FILE_SIZE = 99.megabytes
    ALLOWED_EXTENSIONS = %w[bmp jpeg jpg pdf png tif tiff txt].freeze

    # Internal signal, translated to a 422 in #create.
    class DuplicateUpload < StandardError; end

    # documentTypeId => VBMS document type label
    DOCUMENT_TYPES = {
      26 => 'Buddy/Lay Statement',
      29 => 'Civilian Police Reports',
      34 => 'Correspondence',
      40 => 'Certificate of Release or Discharge From Active Duty (DD214)',
      45 => 'Military Personnel Record',
      58 => 'Medical Treatment Record - Government Facility',
      59 => 'Medical Treatment Record - Non-Government Facility',
      80 => 'Photographs',
      111 => 'VA Form 21-2680',
      116 => 'VA Form 21-4142',
      124 => 'VA Form 21-4192',
      126 => 'VA Form 21-4502',
      142 => 'VA Form 21-674 (Report of School Attendance)',
      148 => 'VA Form 21-686c',
      158 => 'VA Form 21-8940',
      168 => 'VA Form 26-4555',
      375 => 'VA Form 21-0779',
      381 => 'VA Form 21-0781',
      382 => 'VA Form 21-0781a',
      478 => 'Medical Treatment Records - Furnished by SSA',
      702 => 'Disability Benefits Questionnaire (DBQ) - Veteran Provided',
      703 => 'Goldmann Perimetry Chart/Field of Vision Chart',
      827 => 'VA Form 21-4142a'
    }.freeze

    def create
      # Separate locals, not one struct: if a later parse fails, the failure log still
      # has whatever the earlier ones established.
      uploaded_file = parse_uploaded_file
      doc_type_id = parse_document_type_id
      sc_id = parse_supplemental_claim_id

      upload = build_upload_request(uploaded_file, doc_type_id, sc_id)
      copy_and_upload(upload, guard_duplicate_upload(upload))
    rescue ClaimsEvidenceApi::Service::Files::VirusFound => e
      increment_upload_failure(doc_type_id, reason: 'virus')
      log_upload_failure(e, uploaded_file, doc_type_id, sc_id)
      raise Common::Exceptions::UnprocessableEntity.new(
        detail: 'We were unable to process your file. Please try again.',
        source: 'ClaimsEvidenceController#create'
      )
    rescue DuplicateUpload
      # Translate the internal signal into the response; unhandled it would render a 500.
      raise Common::Exceptions::UnprocessableEntity.new(detail: 'DOC_UPLOAD_DUPLICATE', source: self.class.name)
    rescue ClaimsEvidence::PdfUnlocker::Rejected => e
      raise_validation_failure(e.reason, e.code)
    rescue => e
      # sc_id is the last thing param validation sets, so its presence means the failure came
      # from the upload itself; validation failures already counted validation.failure.
      increment_upload_failure(doc_type_id, error_class: e.class.name) if sc_id
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
        file_size: uploaded_file.tempfile.size,
        document_type: DOCUMENT_TYPES[doc_type_id]
      )
    end

    # @return [ClaimsEvidence::DuplicateCheck] holding the lock, for the caller to release
    # detected_by names what the duplicate matched: an upload that already finished, or one
    # still running in a parallel request.
    def guard_duplicate_upload(upload)
      duplicate_check = ClaimsEvidence::DuplicateCheck.new(current_user: @current_user, upload:)

      raise_duplicate(upload, detected_by: 'completed') if duplicate_check.presumed_duplicate?
      raise_duplicate(upload, detected_by: 'in_flight') unless duplicate_check.acquire_lock

      duplicate_check
    end

    def raise_duplicate(upload, detected_by:)
      increment_upload_failure(upload.doc_type_id, reason: 'duplicate', detected_by:)
      raise DuplicateUpload
    end

    # Something about the file itself the Veteran can act on, so it carries a code the frontend
    # can key off rather than a sentence. cause: nil matters for the password rejections, whose
    # underlying error was raised while the password was in scope.
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

    def check_feature_enabled
      routing_error unless Flipper.enabled?(:cst_supplemental_claims_evidence_upload, @current_user)
    end

    def copy_and_upload(upload, duplicate_check)
      evidence_accepted = false
      prefix = File.basename(upload.file_name, '.*').to_s[0, 50].presence || 'claims-evidence'
      Tempfile.create([prefix, File.extname(upload.file_name)]) do |tmp|
        tmp.binmode
        upload.file.tempfile.rewind
        IO.copy_stream(upload.file.tempfile, tmp)
        tmp.flush
        # Decrypt before the virus scan and upload, so both see readable bytes.
        ClaimsEvidence::PdfUnlocker.new(tmp, upload.file_name, password: params[:password]).unlock!
        ce_response = ce_service.upload(tmp.path, provider_data: build_provider_data(upload.doc_type_id))
        # Set the moment Claims Evidence takes the file: from here on nothing may release
        # the lock, because the document is in the eFolder whatever happens next.
        evidence_accepted = true

        # Order matters: save the record first, since the file is already in the eFolder. Build the
        # payload before counting success, so a response body we can't read is only counted as a failure.
        # Once the row exists the first layer takes over, so a failed release costs nothing.
        # If it didn't, hold the lock.
        duplicate_check.release_lock(retry_blocked: false) if persist_evidence_submission(upload, ce_response)
        payload = build_upload_response_payload(ce_response.body)
        log_upload_success(upload.doc_type_id)
        render json: payload, status: ce_response.status
      end
    rescue
      # The file never reached Claims Evidence, so free the lock for an immediate retry. If this
      # release fails the lock is stranded and that retry 422s until the TTL expires.
      duplicate_check.release_lock(retry_blocked: true) unless evidence_accepted
      raise
    end

    def build_upload_response_payload(response_body)
      unless response_body.is_a?(Hash)
        raise TypeError, "Unexpected Claims Evidence response body class: #{response_body.class.name}"
      end

      response_body.slice('uuid', 'currentVersionUuid')
    end

    # Best effort: the file is uploaded and the record is saved by now, so a broken metric or log
    # must not fail the request. Without this, an error here skips the render and #create's rescue
    # turns a successful upload into a 500 with a false failure metric.
    def log_upload_success(doc_type_id)
      StatsD.increment("#{STATSD_METRIC_PREFIX}.upload.success",
                       tags: STATSD_TAGS + ["document_type_id:#{doc_type_id}"])
      Rails.logger.info('ClaimsEvidenceController#create upload success',
                        document_type: DOCUMENT_TYPES[doc_type_id])
    rescue
      nil
    end

    def increment_upload_failure(doc_type_id, **extra_tags)
      tags = STATSD_TAGS + extra_tags.map { |k, v| "#{k}:#{v}" } + ["document_type_id:#{doc_type_id}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.upload.failure", tags:)
    end

    def increment_validation_failure(reason)
      StatsD.increment("#{STATSD_METRIC_PREFIX}.validation.failure", tags: STATSD_TAGS + ["reason:#{reason}"])
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
        increment_validation_failure('malformed_document_type_id')
        raise Common::Exceptions::UnprocessableEntity.new(detail: 'documentTypeId must be an integer')
      end

      unless DOCUMENT_TYPES.key?(doc_type_id)
        increment_validation_failure('unsupported_document_type_id')
        raise Common::Exceptions::UnprocessableEntity.new(detail: "documentTypeId #{doc_type_id} is not supported")
      end

      doc_type_id
    end

    def parse_supplemental_claim_id
      sc_id = params[:supplementalClaimId].presence
      unless sc_id
        increment_validation_failure('missing_supplemental_claim_id')
        raise Common::Exceptions::UnprocessableEntity.new(detail: 'supplementalClaimId is required')
      end

      sc_id = sc_id.to_s
      unless sc_id.match?(/\ASC\d+\z/)
        increment_validation_failure('malformed_supplemental_claim_id')
        raise Common::Exceptions::UnprocessableEntity.new(
          detail: 'supplementalClaimId must be in the format SC followed by digits (e.g. SC10879)'
        )
      end

      sc_id
    end

    # Never fail the upload response because of a persistence miss:
    # the file is already in the eFolder.
    def persist_evidence_submission(upload, ce_response)
      EvidenceSubmission.create!(
        caseflow_claim_id: upload.sc_id,
        user_account: @current_user.user_account,
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
        file_size: upload.file_size,
        delete_date: 60.days.from_now,
        template_metadata: { personalisation: { file_name: upload.file_name,
                                                document_type_id: upload.doc_type_id,
                                                document_type: upload.document_type } }.to_json
      )
    rescue => e
      log_persist_failure(e, { file_name: upload.file_name, sc_id: upload.sc_id,
                               doc_type_id: upload.doc_type_id, file_size: upload.file_size,
                               ce_response: })
      nil # StatsD.increment returns truthy; nil stops the caller releasing the lock
    end

    def log_persist_failure(error, context)
      Rails.logger.error(
        'ClaimsEvidenceController#persist_evidence_submission failed',
        document_type_id: context[:doc_type_id],
        supplemental_claim_id: context[:sc_id],
        error_class: error.class.name,
        error: Logging::Helper::DataScrubber.scrub(error.message)
      )
      StatsD.increment("#{STATSD_METRIC_PREFIX}.persist.failure",
                       tags: STATSD_TAGS + ["error_class:#{error.class.name}"])
      capture_submission_for_backfill(context)
    end

    # The document is already in the eFolder but has no EvidenceSubmission row, and the
    # request still returns 200. Capture everything needed to recreate the row by hand.
    def capture_submission_for_backfill(context)
      ce_body = context[:ce_response]&.body
      PersonalInformationLog.create(
        error_class: 'ClaimsEvidenceController#persist_evidence_submission',
        data: {
          caseflow_claim_id: context[:sc_id],
          user_account_id: @current_user.user_account&.id,
          icn: @current_user.icn,
          document_type_id: context[:doc_type_id],
          document_type: DOCUMENT_TYPES[context[:doc_type_id]],
          file_name: context[:file_name],
          file_size: context[:file_size],
          claims_evidence_uuid: ce_body&.dig('uuid'),
          claims_evidence_current_version_uuid: ce_body&.dig('currentVersionUuid'),
          upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
          delete_date: 60.days.from_now
        }
      )
    rescue => e
      log_backfill_capture_failure(e, context, ce_body)
    end

    # Last line of defense: no EvidenceSubmission row and no PII log, while the document sits
    # in the eFolder. The CE uuid is the only remaining recovery anchor --
    # ClaimsEvidenceApi::Service::Files#retrieve can fetch the document metadata from it
    def log_backfill_capture_failure(error, context, ce_body)
      Rails.logger.error(
        'ClaimsEvidenceController#capture_submission_for_backfill failed',
        supplemental_claim_id: context[:sc_id],
        user_account_uuid: @current_user&.user_account_uuid,
        document_type_id: context[:doc_type_id],
        claims_evidence_uuid: ce_body&.dig('uuid'),
        error_class: error.class.name
      )
      StatsD.increment("#{STATSD_METRIC_PREFIX}.persist.unrecoverable",
                       tags: STATSD_TAGS + ["error_class:#{error.class.name}"])
    end

    def build_provider_data(doc_type_id)
      {
        contentSource: ClaimsEvidenceApi::CONTENT_SOURCE,
        dateVaReceivedDocument: Time.zone.now.in_time_zone(ClaimsEvidenceApi::TIMEZONE).strftime('%Y-%m-%d'),
        documentTypeId: doc_type_id
      }
    end

    def ce_service
      service = ClaimsEvidenceApi::Service::Files.new
      service.folder_identifier = ClaimsEvidenceApi::FolderIdentifier.generate('VETERAN', 'ICN', @current_user.icn)
      service
    end
  end
end
