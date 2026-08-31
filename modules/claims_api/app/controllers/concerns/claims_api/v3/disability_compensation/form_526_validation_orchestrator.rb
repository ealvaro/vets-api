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
          # returning claim_date so it can be used for memoization or further processing
          _claim_date, claim_date_errors = validate_claim_date

          errors.merge(claim_date_errors)
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

        def validate_claim_date
          Sections::ClaimDate.new(
            @form_attributes['claimDate']
          ).validate
        end
      end
    end
  end
end
