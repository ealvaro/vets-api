# frozen_string_literal: true

module Mobile
  module V0
    module Contracts
      class ClaimsAndAppeals < PaginationBase
        params(Schemas::DateRangeSchema) do
          optional(:show_completed).maybe(:bool, :filled?)
        end
      end
    end
  end
end
