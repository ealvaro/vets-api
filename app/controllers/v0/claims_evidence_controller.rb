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

    STATSD_METRIC_PREFIX = 'api.claims_evidence'
    STATSD_TAGS = [
      'service:claims-evidence',
      'team:benefits-management-tools',
      'itportfolio:benefits-delivery',
      'dependency:claims-evidence-api'
    ].freeze
    # Supported Claims Evidence document types, keyed by documentTypeId.
    # Values are the human-readable VBMS document type labels.
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
      uploaded_file = params[:file]
      validate_uploaded_file!(uploaded_file)

      doc_type_id = parse_document_type_id
      sc_id = parse_supplemental_claim_id

      copy_and_upload(uploaded_file, doc_type_id, sc_id)
    rescue ClaimsEvidenceApi::Service::Files::VirusFound => e
      increment_upload_failure(doc_type_id, reason: 'virus')
      log_upload_failure(e, uploaded_file, doc_type_id, sc_id)
      raise Common::Exceptions::UnprocessableEntity.new(
        detail: 'We were unable to process your file. Please try again.',
        source: 'ClaimsEvidenceController#create'
      )
    rescue => e
      # sc_id is the last thing param validation sets, so its presence means the failure came
      # from the upload itself; validation failures already counted validation.failure.
      increment_upload_failure(doc_type_id, error_class: e.class.name) if sc_id
      log_upload_failure(e, uploaded_file, doc_type_id, sc_id)
      raise
    end

    private

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

    def copy_and_upload(uploaded_file, doc_type_id, sc_id)
      original_filename = File.basename(uploaded_file.original_filename.to_s)
      prefix = File.basename(original_filename, '.*').to_s[0, 50].presence || 'claims-evidence'
      Tempfile.create([prefix, File.extname(original_filename)]) do |tmp|
        tmp.binmode
        uploaded_file.tempfile.rewind
        IO.copy_stream(uploaded_file.tempfile, tmp)
        tmp.flush
        ce_response = ce_service.upload(tmp.path, provider_data: build_provider_data(doc_type_id))

        # Order matters: save the record first, since the file is already in the eFolder. Build the
        # payload before counting success, so a response body we can't read is only counted as a failure.
        persist_evidence_submission(original_filename, sc_id, doc_type_id, tmp, ce_response)
        payload = build_upload_response_payload(ce_response.body)
        log_upload_success(doc_type_id)

        render json: payload, status: ce_response.status
      end
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

    def validate_uploaded_file!(uploaded_file)
      if uploaded_file.blank?
        increment_validation_failure('missing_file')
        raise Common::Exceptions::ParameterMissing, 'file'
      end

      return if uploaded_file.class.name.include?('UploadedFile')

      increment_validation_failure('invalid_file')
      raise Common::Exceptions::InvalidFieldValue.new('file', uploaded_file.class.name)
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
    def persist_evidence_submission(file_name, sc_id, doc_type_id, tmp, ce_response)
      document_type = DOCUMENT_TYPES[doc_type_id]
      file_size = File.size(tmp.path)
      EvidenceSubmission.create!(
        caseflow_claim_id: sc_id,
        user_account: @current_user.user_account,
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
        file_size:,
        delete_date: 60.days.from_now,
        template_metadata: { personalisation: { file_name:, document_type: } }.to_json
      )
    rescue => e
      log_persist_failure(e, { file_name:, sc_id:, doc_type_id:, file_size:, ce_response: })
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
