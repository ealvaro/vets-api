# frozen_string_literal: true

module AskVAApi
  module Inquiries
    module Checkpoint
      class Inbound < Base
        def call(request_id:, payload:)
          super(request_id:, payload:, checkpoint_type: :inbound_submission)
        end
      end
    end
  end
end
