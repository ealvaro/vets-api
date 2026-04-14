# frozen_string_literal: true

module AskVAApi
  module Inquiries
    module Checkpoint
      class Inbound < Base
        def call(request_id:, payload:)
          super(
            request_id:,
            payload: normalize_payload(payload),
            checkpoint_type: :inbound_submission
          )
        end

        private

        def normalize_payload(payload)
          payload.deep_dup.with_indifferent_access.tap do |normalized_payload|
            files = normalized_payload[:files]

            if normalized_payload.key?(:files)
              normalized_payload[:attachment_count] = files.is_a?(Array) ? files.count : 0
              normalized_payload.delete(:files)
            end
          end
        end
      end
    end
  end
end
