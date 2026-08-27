# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      class Errors
        attr_reader :messages

        def initialize(base_source: '')
          @base_source = base_source
          @messages = []
        end

        def add(source:, detail:, title: 'Unprocessable Entity', status: '422')
          full_source = @base_source.empty? ? source : "#{@base_source}#{source}"
          @messages << { detail:, source: full_source, title:, status: }
        end

        def merge(other)
          @messages.concat(other.messages)
        end

        def any?
          @messages.any?
        end

        def presence
          @messages.presence
        end
      end
    end
  end
end
