# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        class ServicePeriod
          def initialize(value, source:)
            @source = source
            @entry_date = FullDate.new(value&.dig('entryDate'), source: "#{source}/entryDate")
            @exit_date = FullDate.new(value&.dig('exitDate'), source: "#{source}/exitDate")
          end

          def validate(errors:)
            validate_dates(errors:)
          end

          private

          def validate_dates(errors:)
            return unless @entry_date.date_present?

            @entry_date.validate(errors:)
            return unless @entry_date.valid?

            return unless @exit_date.date_present?

            @exit_date.validate(errors:)
            return unless @exit_date.valid?

            if @entry_date.parse >= @exit_date.parse
              errors.add(
                source: "#{@source}/exitDate",
                detail: 'exitDate needs to be after entryDate.'
              )
            end
          end
        end
      end
    end
  end
end
