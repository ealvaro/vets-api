# frozen_string_literal: true

require 'logging/third_party_transaction'
require 'disability_compensation/validators/document_validator'

module V0
  class UploadSupportingEvidencesController < ApplicationController
    include FormAttachmentCreate
    extend Logging::ThirdPartyTransaction::MethodWrapper
    service_tag 'disability-application'

    FORM_ATTACHMENT_MODEL = SupportingEvidenceAttachment
    STATSD_KEY_PREFIX = 'api.form526.supporting_evidence'

    wrap_with_logging(
      :save_attachment_to_cloud!,
      additional_class_logs: {
        form: '526ez supporting evidence attachment',
        action: "upload: #{FORM_ATTACHMENT_MODEL}",
        upstream: 'User provided file',
        downstream: "S3 bucket: #{Settings.evss.s3.bucket}"
      },
      additional_instance_logs: {
        user_uuid: %i[current_user account_uuid]
      }
    )

    def create
      super

      unless document_validation_enabled?
        StatsD.increment("#{STATSD_KEY_PREFIX}.upload", tags: ['validation:skipped_flipper_disabled'])
        return
      end

      if filtered_params[:attachment_id].blank?
        StatsD.increment("#{STATSD_KEY_PREFIX}.upload", tags: ['validation:skipped_no_attachment_id'])
        return
      end

      StatsD.increment("#{STATSD_KEY_PREFIX}.upload", tags: ['validation:performed'])
      append_validation_result!
    end

    private

    def serializer_klass
      SupportingEvidenceAttachmentSerializer
    end

    def filtered_params
      @filtered_params ||= params.require(:supporting_evidence_attachment)
                                 .permit(:file_data, :password, :attachment_id)
    end

    def run_document_validation
      file_path = filtered_params[:file_data].tempfile.path
      validator = DisabilityCompensation::Validators::DocumentValidator.new(
        file_path,
        attachment_id: filtered_params[:attachment_id],
        in_progress_form_id:
      )
      validator.validate
    end

    def document_validation_enabled?
      Flipper.enabled?(:disability_526_document_validation_enabled, current_user)
    end

    def append_validation_result!
      body = JSON.parse(response.body)
      attributes = body.dig('data', 'attributes') || {}
      attributes['warnings'] = run_document_validation
      body['data'] ||= {}
      body['data']['attributes'] = attributes
      self.response_body = body.to_json
    end

    def in_progress_form_id
      InProgressForm.form_for_user(FormProfiles::VA526ez::FORM_ID, current_user)&.id
    end
  end
end
