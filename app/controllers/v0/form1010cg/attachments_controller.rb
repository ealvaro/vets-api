# frozen_string_literal: true

module V0
  module Form1010cg
    class AttachmentsController < ApplicationController
      include FormAttachmentCreate
      service_tag 'caregiver-application'

      DECRYPTION_ERROR_MESSAGE = 'The password you entered is incorrect. Please try again.'

      skip_before_action :authenticate, raise: false
      rescue_from Common::Exceptions::UnprocessableEntity, with: :handle_unprocessable_entity

      FORM_ATTACHMENT_MODEL = ::Form1010cg::Attachment

      private

      def serializer_klass
        ::Form1010cg::AttachmentSerializer
      end

      def handle_unprocessable_entity(exception)
        is_pdf_unlock_error = exception.errors.first&.source == 'Common::PdfHelpers.unlock_pdf'

        if is_pdf_unlock_error
          Rails.logger.info(
            '[Form 10-10CG] Attachment decryption failed',
            encrypted: true,
            source: exception.errors.first&.source
          )

          render json: {
            errorMessage: DECRYPTION_ERROR_MESSAGE,
            isEncrypted: true
          }, status: :unprocessable_entity
        else
          render_errors(exception)
        end
      end
    end
  end
end
