# frozen_string_literal: true

require 'claims_evidence_api/exceptions'
require 'claims_evidence_api/folder_identifier'
require 'claims_evidence_api/service/files'
require 'lighthouse/benefits_documents/constants'
require 'logging/helper/data_scrubber'

module ClaimsEvidence
  class UploadEvidence
    RELATIVE_SCAN_DIR = 'clamav_tmp'
    STATUS = BenefitsDocuments::Constants::UPLOAD_STATUS

    class DuplicateUpload < StandardError
      def code = 'DOC_UPLOAD_DUPLICATE'
    end

    # The name is taken in the eFolder by a document that is not this one
    class ContentNameTaken < StandardError
      def code = 'DOC_UPLOAD_NAME_TAKEN'
    end

    # What the controller renders once the file is filed.
    Result = Data.define(:payload, :status)

    # @param current_user [User]
    # @param upload [ClaimsEvidence::UploadRequest] the validated file and its metadata
    # @param password [String, nil] supplied by the Veteran for an encrypted PDF
    def initialize(current_user:, upload:, password: nil)
      @current_user = current_user
      @upload = upload
      @password = password
      @filed = false
    end

    # @return [Result]
    # @raise [DuplicateUpload] the same file is already filed, or is mid-flight in another request
    # @raise [ContentNameTaken] the name belongs to a different document in the eFolder
    # @raise [ClaimsEvidence::ContentName::Unsupported] nothing usable survived transliteration
    # @raise [ClaimsEvidence::PdfUnlocker::Rejected] something about the PDF the Veteran can fix
    # @raise [ClaimsEvidenceApi::Service::Files::VirusFound]
    def call
      copy_and_upload(guard_duplicate_upload)
    rescue DuplicateUpload, ClaimsEvidence::PdfUnlocker::Rejected
      # Already counted where it was raised, or counted by the controller as a validation
      # failure.
      raise
    rescue ContentNameTaken
      increment_upload_failure(reason: 'content_name_taken')
      raise
    rescue ClaimsEvidence::ContentName::Unsupported
      increment_upload_failure(reason: 'unsupported_name')
      raise
    rescue ClaimsEvidenceApi::Service::Files::VirusFound
      increment_upload_failure(reason: 'virus')
      raise
    rescue => e
      increment_upload_failure(error_class: e.class.name)
      raise
    end

    private

    # @return [ClaimsEvidence::DuplicateCheck] holding the lock, for the caller to release
    def guard_duplicate_upload
      duplicate_check = ClaimsEvidence::DuplicateCheck.new(current_user: @current_user, upload: @upload)

      raise_duplicate(detected_by: 'completed') if duplicate_check.presumed_duplicate?
      raise_duplicate(detected_by: 'in_flight') unless duplicate_check.acquire_lock

      duplicate_check
    end

    def raise_duplicate(detected_by:)
      increment_upload_failure(reason: 'duplicate', detected_by:)
      raise DuplicateUpload
    end

    def copy_and_upload(duplicate_check)
      prefix = File.basename(@upload.file_name, '.*').to_s[0, 50].presence || 'claims-evidence'
      FileUtils.mkdir_p(Rails.root.join(RELATIVE_SCAN_DIR))
      Tempfile.create([prefix, File.extname(@upload.file_name)], RELATIVE_SCAN_DIR) do |tmp|
        tmp.binmode
        @upload.file.tempfile.rewind
        IO.copy_stream(@upload.file.tempfile, tmp)
        tmp.flush
        # Decrypt before the virus scan and upload, so both see readable bytes.
        ClaimsEvidence::PdfUnlocker.new(tmp, @upload.file_name, password: @password).unlock!

        ce_response = file_document(tmp.path)

        duplicate_check.release_lock(retry_blocked: false)
        payload = build_upload_response_payload(ce_response.body)
        log_upload_success
        Result.new(payload:, status: ce_response.status)
      end
    rescue
      duplicate_check.release_lock(retry_blocked: !@filed)
      raise
    end

    def file_document(file_path)
      content_name = ClaimsEvidence::ContentName.sanitize(@upload.file_name)
      submission = create_submission(content_name)

      response = upload_document(file_path, content_name)
      mark_filed(submission)
      response
    rescue => e
      submission&.destroy if definite_rejection?(e)
      raise
    end

    # ClientError covers 4xx, 5xx, dropped connections and unreadable responses. Only a 4xx means
    # the document was not filed. ParsingError is a ClientError and can arrive with a 200.
    def definite_rejection?(error)
      return false if error.is_a?(Common::Client::Errors::ParsingError)

      case error
      when ClaimsEvidenceApi::Service::Files::VirusFound, ContentNameTaken then true
      when Common::Client::Errors::ClientError then error.status.to_i.between?(400, 499)
      else false
      end
    end

    # delete_date here is the ceiling for a row that never reaches SUCCESS, whose outcome we never
    # established. mark_filed resets it from the moment the document was actually filed.
    def create_submission(content_name)
      EvidenceSubmission.create!(
        caseflow_claim_id: @upload.sc_id,
        user_account: @current_user.user_account,
        upload_status: STATUS[:CREATED],
        file_size: @upload.file_size,
        delete_date: 60.days.from_now,
        template_metadata: {
          personalisation: {
            file_name: @upload.file_name,
            content_name:,
            document_type_id: @upload.doc_type_id,
            document_type: @upload.document_type
          }
        }.to_json
      )
    end

    def upload_document(file_path, content_name)
      ce_service.upload(file_path, provider_data: build_provider_data, content_name:)
    rescue Common::Client::Errors::ClientError => e
      raise unless duplicate_content_name?(e)

      raise ContentNameTaken
    end

    def duplicate_content_name?(error)
      code = error.body.is_a?(Hash) ? error.body['code'] : nil
      code == ClaimsEvidenceApi::Exceptions::VefsError::DUPLICATE_CONTENT_NAME
    end

    # Retention runs from successful submission, not from creation, so the clock restarts here --
    # any delay in getting the document filed extends it. Identical to the creation value in the
    # synchronous path, where the two happen in the same request.
    def mark_filed(submission)
      submission&.update!(upload_status: STATUS[:SUCCESS], delete_date: 60.days.from_now)
      @filed = true
    rescue => e
      # The document is filed; only the record lagged. The reconciliation job resolves it, so
      # this must not fail a request that did everything it was asked to.
      log_persist_failure(e)
      @filed = true
    end

    def log_persist_failure(error)
      Rails.logger.error(
        'ClaimsEvidence::UploadEvidence could not update the evidence submission',
        document_type_id: @upload.doc_type_id,
        supplemental_claim_id: @upload.sc_id,
        error_class: error.class.name,
        error: Logging::Helper::DataScrubber.scrub(error.message)
      )
      ClaimsEvidence::Metrics.increment('persist.failure', error_class: error.class.name)
    end

    def build_upload_response_payload(response_body)
      unless response_body.is_a?(Hash)
        raise TypeError, "Unexpected Claims Evidence response body class: #{response_body.class.name}"
      end

      response_body.slice('uuid', 'currentVersionUuid')
    end

    # Best effort: the file is uploaded and the record is saved by now, so a broken metric or log
    # must not turn a successful upload into a 500.
    def log_upload_success
      ClaimsEvidence::Metrics.increment('upload.success', document_type_id: @upload.doc_type_id)
      Rails.logger.info('ClaimsEvidenceController#create upload success',
                        document_type: @upload.document_type)
    rescue
      nil
    end

    def increment_upload_failure(**extra_tags)
      ClaimsEvidence::Metrics.increment('upload.failure', **extra_tags,
                                        document_type_id: @upload.doc_type_id)
    end

    def build_provider_data
      {
        contentSource: ClaimsEvidenceApi::CONTENT_SOURCE,
        dateVaReceivedDocument: Time.zone.now.in_time_zone(ClaimsEvidenceApi::TIMEZONE).strftime('%Y-%m-%d'),
        documentTypeId: @upload.doc_type_id
      }
    end

    def folder_identifier
      @folder_identifier ||= ClaimsEvidenceApi::FolderIdentifier.generate('VETERAN', 'ICN', @current_user.icn)
    end

    def ce_service
      @ce_service ||= ClaimsEvidenceApi::Service::Files.new.tap { |s| s.folder_identifier = folder_identifier }
    end
  end
end
