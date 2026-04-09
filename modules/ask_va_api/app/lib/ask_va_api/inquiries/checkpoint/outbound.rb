# frozen_string_literal: true

module AskVAApi
  module Inquiries
    module Checkpoint
      class Outbound < Base
        def call(request_id:, payload:)
          super(request_id:, payload:, checkpoint_type: :outbound_submission)
        end
      end
    end
  end
end
