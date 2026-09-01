# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        class FullDate
          FULL_DATE_REGEX = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/

          def initialize(value, source:)
            @value = value
            @source = source
          end

          def validate(errors:)
            return if @value.blank?
            return if valid?

            errors.add(source: @source, detail: "#{@value} is not a valid date.")
          end

          def valid?
            return false if @value.blank?
            return false unless @value.match?(FULL_DATE_REGEX)

            y, m, d = @value.split('-').map(&:to_i)
            ::Date.valid_date?(y, m, d)
          end

          def date_present?
            @value.present?
          end

          def parse
            ::Date.strptime(@value, '%Y-%m-%d')
          end
        end
      end
    end
  end
end
