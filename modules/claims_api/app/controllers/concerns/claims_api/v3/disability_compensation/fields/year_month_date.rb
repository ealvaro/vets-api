# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        module YearMonthDate
          module_function

          def call(value, source:, errors:)
            return if value.nil?
            return unless Date.parse("#{value}-01") > Date.current

            errors.add(source:, detail: 'approximateDate must be a date in the past.')
          end
        end
      end
    end
  end
end
