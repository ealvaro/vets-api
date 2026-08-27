# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        module ServiceNumber
          MAX_LENGTH = 9

          module_function

          def call(value, source:, errors:)
            return if value.nil?
            return if value.length <= MAX_LENGTH

            errors.add(source:, detail: 'serviceNumber is too long.')
          end
        end
      end
    end
  end
end
