# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Rules
        # Cross-section: claimDate × serviceInformation.servicePeriods.exitDate
        module ClaimDateToEndDate
          RESERVES_COMPONENT_NAMES = %w[RESERVES NATIONAL_GUARD].freeze

          module_function

          def call(service_periods, claim_date:, errors:)
            return if service_periods.blank? || claim_date.nil?

            max_period = service_periods.max_by { |sp| sp['exitDate'].to_s }
            max_end_date_str = max_period&.dig('exitDate')
            return if max_end_date_str.blank?

            max_exit = Fields::FullDate.new(max_end_date_str, source: '/serviceInformation/servicePeriods')
            return unless max_exit.valid?

            return unless max_exit.parse > claim_date + 180.days
            return if eligible_for_future_end_date?(max_period, service_periods, claim_date)

            errors.add(
              source: '/serviceInformation/servicePeriods',
              detail: 'Service members cannot submit a claim until they are within 180 days of their separation date.'
            )
          end

          def eligible_for_future_end_date?(max_period, service_periods, claim_date)
            most_recent_component_is_reserves_or_guard?(max_period) && past_service_period?(service_periods, claim_date)
          end

          def most_recent_component_is_reserves_or_guard?(max_period)
            components = max_period['component'] || []
            components.any? { |c| RESERVES_COMPONENT_NAMES.include?(c.upcase.tr(' ', '_')) }
          end

          def past_service_period?(service_periods, claim_date)
            return false if service_periods.blank?

            service_periods.any? do |sp|
              exit_date = Fields::FullDate.new(sp['exitDate'], source: '/serviceInformation/servicePeriods')
              next false unless exit_date.valid?

              exit_date.parse <= claim_date
            end
          end
        end
      end
    end
  end
end
