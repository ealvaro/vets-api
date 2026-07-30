# frozen_string_literal: true

require 'pdf_forms'
require 'tempfile'
require 'benefits_documents/providers/benefits_documents_provider'
require 'lighthouse/benefits_documents/constants'
require 'lighthouse/benefits_documents/utilities/helpers'

module BenefitsDocuments
  module Providers
    module IvcChampva
      class IvcChampvaBenefitsDocumentsProvider
        include BenefitsDocuments::Providers::BenefitsDocumentsProvider

        SUPPORTED_FORM_IDS = %w[
          10-10D
          10-10D-EXTENDED
          10-10D-SUPPLEMENTAL
          10-10D-SUPPLEMENTAL-EXISTING
          10-10D-SUPPLEMENTAL-ENROLLMENT
          10-7959C
          10-7959F-2
          10-7959A
        ].freeze
        DOCS_ONLY_RESUBMISSION_FLAG = :benefits_documents_ivc_champva_docs_only_resubmission

        def initialize(current_user)
          @current_user = current_user
        end

        def queue_document_upload(params)
          claim_id = params[:claim_id].presence || params[:benefits_claim_id].presence
          claim_record = resolve_claim_record(claim_id)
          form_id = resolve_form_id(claim_record.form_number)

          attachment = PersistentAttachments::MilitaryRecords.new(form_id:)
          attachment.file = unlocked_file(params[:file], params[:password])

          raise Common::Exceptions::ValidationErrors, attachment unless attachment.valid?

          attachment.save
          persist_evidence_submission(claim_record.id, params[:file], attachment, params)
          submit_docs_only_resubmission!(claim_record, attachment, params)

          { jid: attachment.guid }
        end

        private

        def resolve_claim_record(raw_claim_id)
          claim_id = raw_claim_id.to_s
          raise Common::Exceptions::ResourceNotFound if claim_id.blank?

          if claim_id.match?(/\A\d+\z/)
            record = IvcChampvaForm.find_by(id: claim_id.to_i)
            raise Common::Exceptions::ResourceNotFound if record.blank?

            return verify_claim_ownership!(record)
          end

          record = IvcChampvaForm.where(form_uuid: claim_id).order(updated_at: :desc).first
          raise Common::Exceptions::ResourceNotFound if record.blank?

          verify_claim_ownership!(record)
        end

        def verify_claim_ownership!(record)
          if record.submitted_by_icn.present? && record.submitted_by_icn != @current_user&.icn
            raise Common::Exceptions::ResourceNotFound
          end

          record
        end

        def resolve_form_id(form_number)
          normalized = form_number.to_s.upcase.strip
          return '10-10D-EXTENDED' if normalized.start_with?('10-10D-EXTENDED')
          return normalized if SUPPORTED_FORM_IDS.include?(normalized)

          raise Common::Exceptions::UnprocessableEntity.new(
            detail: "Unsupported CHAMPVA form_number: #{form_number}",
            source: self.class.name
          )
        end

        def unlocked_file(file, password)
          return file unless file_inputs_are_valid?(file, password)

          pdftk = PdfForms.new(Settings.binaries.pdftk)
          tmpf = Tempfile.new(['decrypted_form_attachment', '.pdf'])

          begin
            pdftk.call_pdftk(file.tempfile.path, 'input_pw', password, 'output', tmpf.path)
          rescue PdfForms::PdftkError
            raise Common::Exceptions::UnprocessableEntity.new(
              detail: I18n.t('errors.messages.uploads.pdf.incorrect_password'),
              source: self.class.name
            )
          end

          file.tempfile.unlink
          file.tempfile = tmpf
          file
        end

        def file_inputs_are_valid?(file, password)
          file_param_valid = file.present? && file.respond_to?(:tempfile) && file.respond_to?(:original_filename) &&
                             File.extname(file.original_filename.to_s).downcase == '.pdf'
          password_param_valid = password.present? && password.is_a?(String)
          file_param_valid && password_param_valid
        end

        def persist_evidence_submission(claim_id, source_file, attachment, params)
          current_user_account = user_account
          return if current_user_account.blank?

          file_name = uploaded_file_name(source_file, attachment)
          return if file_name.blank?

          EvidenceSubmission.create(
            claim_id:,
            tracked_item_id: nil,
            upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED],
            user_account: current_user_account,
            template_metadata: template_metadata(file_name, params).to_json
          )
        rescue => e
          Rails.logger.error('Failed to persist CHAMPVA evidence submission', exception: e)
        end

        def user_account
          return nil if @current_user&.user_account_uuid.blank?

          UserAccount.find_by(id: @current_user.user_account_uuid)
        end

        def uploaded_file_name(source_file, attachment)
          attachment_file = attachment.file
          return source_file.original_filename if source_file.respond_to?(:original_filename)
          return attachment_file.original_filename if attachment_file.respond_to?(:original_filename)
          return attachment_file.metadata['filename'] if attachment_file.respond_to?(:metadata)
          return File.basename(attachment_file.path) if attachment_file.respond_to?(:path)

          nil
        end

        def template_metadata(file_name, params)
          document_type = params[:attachment_id].presence || params[:document_type].presence || 'Supporting document'

          {
            personalisation: {
              document_type:,
              file_name:,
              obfuscated_file_name: BenefitsDocuments::Utilities::Helpers.generate_obscured_file_name(file_name),
              date_submitted: BenefitsDocuments::Utilities::Helpers.format_date_for_mailers(Time.zone.now),
              date_failed: nil
            }
          }
        end

        def submit_docs_only_resubmission!(claim_record, attachment, params)
          return unless Flipper.enabled?(DOCS_ONLY_RESUBMISSION_FLAG, @current_user)

          payload = docs_only_resubmission_payload(claim_record, attachment, params)
          response = ::IvcChampva::DocsOnlyResubmissionService.new(current_user: @current_user).call(payload)
          return if response[:status].to_i == 200

          error_message = response.dig(:json, :error_message)
          detail = 'CHAMPVA docs-only resubmission failed'
          detail = "#{detail}: #{error_message}" if error_message.present?

          raise Common::Exceptions::UnprocessableEntity.new(
            detail:,
            source: self.class.name
          )
        end

        def docs_only_resubmission_payload(claim_record, attachment, params)
          attachment_id = params[:attachment_id].presence || params[:document_type].presence || 'Supporting document'
          uploaded_name = uploaded_file_name(params[:file], attachment)

          {
            'form_number' => '10-10D-EXTENDED',
            'submission_type' => 'existing',
            'claim_id' => claim_record.form_uuid,
            'supporting_docs' => [
              {
                'confirmation_code' => attachment.guid,
                'attachment_id' => attachment_id,
                'name' => uploaded_name
              }
            ]
          }
        end
      end
    end
  end
end
