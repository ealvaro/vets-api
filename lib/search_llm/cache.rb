# frozen_string_literal: true

module SearchLlm
  module Cache
    def self.key(search_id)
      "search:llm_response:#{search_id}"
    end
  end
end
