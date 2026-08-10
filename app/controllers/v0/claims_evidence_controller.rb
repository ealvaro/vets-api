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
      if uploaded_file.blank?
        increment_validation_failure('missing_file')
        raise Common::Exceptions::ParameterMissing, 'file'
      end

      unless uploaded_file.class.name.include?('UploadedFile')
        increment_validation_failure('invalid_file')
        raise Common::Exceptions::InvalidFieldValue.new('file', uploaded_file.class.name)
      end

      doc_type_id = parse_document_type_id
      sc_id = parse_supplemental_claim_id

      copy_and_upload(uploaded_file, doc_type_id, sc_id)
    rescue => e
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
        ce_response = perform_ce_upload(tmp, doc_type_id)

        persist_evidence_submission(original_filename, sc_id, doc_type_id, tmp)
        StatsD.increment("#{STATSD_METRIC_PREFIX}.upload.success",
                         tags: ["document_type_id:#{doc_type_id}"])
        render json: ce_response.body.slice('uuid', 'currentVersionUuid'), status: ce_response.status
      end
    end

    # Calls the Claims Evidence upload and emits failure metrics for exceptions.
    # Success metrics fire in the caller after inspecting response status.
    def perform_ce_upload(tmp, doc_type_id)
      ce_service.upload(tmp.path, provider_data: build_provider_data(doc_type_id))
    rescue ClaimsEvidenceApi::Service::Files::VirusFound
      increment_upload_failure(doc_type_id, reason: 'virus')
      raise Common::Exceptions::UnprocessableEntity.new(
        detail: 'We were unable to process your file. Please try again.',
        source: 'ClaimsEvidenceController#create'
      )
    rescue => e
      increment_upload_failure(doc_type_id, error_class: e.class.name)
      raise
    end

    def increment_upload_failure(doc_type_id, **extra_tags)
      tags = extra_tags.map { |k, v| "#{k}:#{v}" } + ["document_type_id:#{doc_type_id}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.upload.failure", tags:)
    end

    def increment_validation_failure(reason)
      StatsD.increment("#{STATSD_METRIC_PREFIX}.validation.failure", tags: ["reason:#{reason}"])
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
    # the file is already in the eFolder; a DB error here shouldn't 500 the user.
    def persist_evidence_submission(file_name, sc_id, doc_type_id, tmp)
      document_type = DOCUMENT_TYPES[doc_type_id]
      EvidenceSubmission.create!(
        caseflow_claim_id: sc_id,
        user_account: @current_user.user_account,
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
        file_size: File.size(tmp.path),
        delete_date: 60.days.from_now,
        template_metadata: { personalisation: { file_name:, document_type: } }.to_json
      )
    rescue => e
      Rails.logger.error(
        'ClaimsEvidenceController#persist_evidence_submission failed',
        document_type_id: doc_type_id,
        supplemental_claim_id: sc_id,
        error_class: e.class.name,
        error: Logging::Helper::DataScrubber.scrub(e.message)
      )
      StatsD.increment("#{STATSD_METRIC_PREFIX}.persist.failure", tags: ["error_class:#{e.class.name}"])
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
