# frozen_string_literal: true

module AskVAApi
  module Inquiries
    module Checkpoint
      class Base
        def call(request_id:, payload:, checkpoint_type:)
          AskVAApi::InquirySubmission.transaction do
            inquiry_submission = AskVAApi::InquirySubmission.find_or_create_by!(request_id:)
            AskVAApi::InquirySubmissionCheckpoint.create!(
              inquiry_submission:,
              checkpoint_type:,
              payload:
            )
          end
        end
      end
    end
  end
end
