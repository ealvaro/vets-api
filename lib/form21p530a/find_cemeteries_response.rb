# frozen_string_literal: true

module Form21p530a
  class FindCemeteriesResponse
    attr_reader :response

    def initialize(response)
      @response = response
    end

    def cache?
      @response.is_a?(Array) && @response.size.positive?
    end
  end
end
