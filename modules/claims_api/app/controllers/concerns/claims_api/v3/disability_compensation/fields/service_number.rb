# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        class ServiceNumber
          MAX_LENGTH = 9

          def initialize(value, source:)
            @value = value
            @source = source
          end

          def validate(errors:)
            return if @value.nil?
            return if @value.length <= MAX_LENGTH

            errors.add(source: @source, detail: 'serviceNumber is too long.')
          end
        end
      end
    end
  end
end
