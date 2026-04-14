# frozen_string_literal: true

module AskVAApi
  module Inquiries
    module Checkpoint
      class Outbound < Base
        def call(request_id:, payload:)
          super(
            request_id:,
            payload: normalize_payload(payload),
            checkpoint_type: :outbound_submission
          )
        end

        private

        def normalize_payload(payload)
          payload.deep_dup.with_indifferent_access.tap do |normalized_payload|
            attachments = normalized_payload[:ListOfAttachments]

            if normalized_payload.key?(:ListOfAttachments)
              normalized_payload[:AttachmentCount] = attachments.is_a?(Array) ? attachments.count : 0
              normalized_payload.delete(:ListOfAttachments)
            end
          end
        end
      end
    end
  end
end
