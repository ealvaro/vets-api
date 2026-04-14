# frozen_string_literal: true

module AskVAApi
  module Inquiries
    module Checkpoint
      class CrmResponse < Base
        def call(request_id:, payload:)
          normalized = normalize_payload(payload)
          crm_message_id = normalized[:MessageId]
          inquiry_number = normalized.dig(:Data, :InquiryNumber)

          super(
            request_id:,
            payload: normalized,
            checkpoint_type: :crm_response
          )

          update_inquiry_submission_record(request_id:, crm_message_id:, inquiry_number:)
        end

        private

        def update_inquiry_submission_record(request_id:, crm_message_id:, inquiry_number:)
          attributes = { crm_message_id: }
          attributes[:inquiry_number] = inquiry_number unless inquiry_number.nil?

          AskVAApi::InquirySubmission
            .find_by!(request_id:)
            .update!(attributes)
        end

        def normalize_payload(payload)
          payload.deep_dup.with_indifferent_access.tap do |normalized_payload|
            data = normalized_payload[:Data]&.with_indifferent_access
            next if data.blank?

            normalized_payload[:Data] = data
            list_of_attachments = data[:ListOfAttachments]
            data[:AttachmentCount] = list_of_attachments.is_a?(Array) ? list_of_attachments.count : 0
          end
        end
      end
    end
  end
end
