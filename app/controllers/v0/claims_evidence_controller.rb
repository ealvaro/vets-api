# frozen_string_literal: true

require 'claims_evidence_api/service/files'
require 'claims_evidence_api/folder_identifier'

module V0
  class ClaimsEvidenceController < ApplicationController
    service_tag 'claims-evidence'
    before_action :check_feature_enabled
    before_action { authorize :claims_evidence, :access? }

    SUPPORTED_DOCUMENT_TYPE_IDS = [
      26, 29, 34, 40, 45, 58, 59, 80, 111, 116,
      124, 126, 142, 148, 158, 168, 375, 381, 382, 478,
      702, 703, 827
    ].to_set.freeze

    def create
      uploaded_file = params.require(:file)
      unless uploaded_file.class.name.include?('UploadedFile')
        raise Common::Exceptions::InvalidFieldValue.new('file', uploaded_file.class.name)
      end

      doc_type_id = parse_document_type_id

      copy_and_upload(uploaded_file, doc_type_id)
    end

    private

    def check_feature_enabled
      routing_error unless Flipper.enabled?(:cst_supplemental_claims_evidence_upload, @current_user)
    end

    def copy_and_upload(uploaded_file, doc_type_id)
      original_filename = File.basename(uploaded_file.original_filename.to_s)
      prefix = File.basename(original_filename, '.*').to_s[0, 50].presence || 'claims-evidence'
      Tempfile.create([prefix, File.extname(original_filename)]) do |tmp|
        tmp.binmode
        uploaded_file.tempfile.rewind
        IO.copy_stream(uploaded_file.tempfile, tmp)
        tmp.flush
        begin
          ce_response = ce_service.upload(tmp.path, provider_data: build_provider_data(doc_type_id))
        rescue ClaimsEvidenceApi::Service::Files::VirusFound
          raise Common::Exceptions::UnprocessableEntity.new(
            detail: 'We were unable to process your file. Please try again.',
            source: 'ClaimsEvidenceController#create'
          )
        end
        render json: ce_response.body.slice('uuid', 'currentVersionUuid'), status: ce_response.status
      end
    end

    def parse_document_type_id
      doc_type_id = begin
        Integer(params.require(:documentTypeId))
      rescue ArgumentError, TypeError
        raise Common::Exceptions::UnprocessableEntity.new(detail: 'documentTypeId must be an integer')
      end

      unless SUPPORTED_DOCUMENT_TYPE_IDS.include?(doc_type_id)
        raise Common::Exceptions::UnprocessableEntity.new(detail: "documentTypeId #{doc_type_id} is not supported")
      end

      doc_type_id
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
