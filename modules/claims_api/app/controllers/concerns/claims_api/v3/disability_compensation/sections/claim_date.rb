# frozen_string_literal: true

# validated parsed Fields::ClaimDate value follows rules of being present
# and not being a future date
module ClaimsApi
  module V3
    module DisabilityCompensation
      module Sections
        class ClaimDate
          CLAIM_DATE_SOURCE = '/claimDate'

          def initialize(value)
            @value = value || ''
            @errors = Errors.new
          end

          # returns errors and claim_date so that claim_date can be memoized
          # the claim_date is parsed and validated by Fields::ClaimDate
          def validate
            claim_date = Fields::ClaimDate.new(@value, source: CLAIM_DATE_SOURCE).validate
            validate_non_future_claim_date(claim_date)

            [claim_date, @errors]
          end

          private

          # formated claim_date will never be blank since it falls back to Date.current if valid
          def validate_non_future_claim_date(claim_date)
            return if claim_date <= Date.current

            @errors.add(source: CLAIM_DATE_SOURCE, detail: 'Claim date cannot be in the future')
          end
        end
      end
    end
  end
end
