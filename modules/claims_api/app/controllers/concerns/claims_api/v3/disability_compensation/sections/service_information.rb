# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Sections
        class ServiceInformation
          def initialize(payload)
            @payload = payload || {}
          end

          def validate
            errors = Errors.new(base_source: '/serviceInformation')
            return errors if @payload.empty?

            validate_service_periods(errors)

            errors
          end

          private

          def validate_service_periods(errors)
            service_periods = @payload['servicePeriods']
            return if service_periods.blank?

            validate_service_periods_quantity(service_periods, errors)

            service_periods.each_with_index do |sp, idx|
              Fields::ServicePeriod.new(sp, source: "/servicePeriods/#{idx}").validate(errors:)
            end
          end

          def validate_service_periods_quantity(service_periods, errors)
            count = service_periods.size
            return if count <= 100

            errors.add(
              source: '/servicePeriods',
              detail: "Number of service periods #{count} must be less than or equal to 100"
            )
          end
        end
      end
    end
  end
end
