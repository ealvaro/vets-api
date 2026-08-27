# frozen_string_literal: true

require 'claims_api/v2/disability_compensation_shared_service_module'

module ClaimsApi
  module V3
    module DisabilityCompensation
      class Form526ValidationOrchestrator
        include ClaimsApi::V2::DisabilityCompensationSharedServiceModule

        def initialize(form_attributes)
          @form_attributes = form_attributes
        end

        def validate
          return if @form_attributes.empty?

          errors = Errors.new

          errors.merge(validate_veteran_identification)
          # ex: errors.merge(validate_service_information)

          errors.presence
        end

        private

        def validate_veteran_identification
          Sections::VeteranIdentification.new(
            @form_attributes['veteranIdentification'],
            valid_countries:
          ).validate
        end
      end
    end
  end
end
