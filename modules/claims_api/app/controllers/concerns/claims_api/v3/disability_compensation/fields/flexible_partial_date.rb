# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        module FlexiblePartialDate
          YEAR_LENGTH = 4
          YEAR_MONTH_LENGTH = 7

          module_function

          def call(value, source:, errors:)
            return if value.nil?

            parsed = case value.length
                     when YEAR_LENGTH then Date.parse("#{value}-01-01")
                     when YEAR_MONTH_LENGTH then Date.parse("#{value}-01")
                     else Date.parse(value)
                     end
            return unless parsed > Date.current

            errors.add(source:, detail: 'approximateDate must be a date in the past.')
          rescue ArgumentError, TypeError
            errors.add(source:, detail: "#{value} is not a valid date.")
          end
        end
      end
    end
  end
end
