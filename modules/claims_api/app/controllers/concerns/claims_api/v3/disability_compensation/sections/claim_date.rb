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

          # returns Array<Hash> of errors, empty array on success
          # raises JsonFormValidationError if the date format itself is invalid,
          # halting all other validation (see Fields::ClaimDate)
          def validate
            claim_date_field.validate

            validate_non_future_claim_date(claim_date)

            @errors.messages
          end

          # memoized here — this is the one place @claim_date is set
          # Exposed for downstream cross-section rules.
          def claim_date
            @claim_date ||= claim_date_field.parse
          end

          private

          # memoized so #validate and #claim_date share one Fields::ClaimDate
          # instance instead of each parsing @value separately
          def claim_date_field
            @claim_date_field ||= Fields::ClaimDate.new(@value, source: CLAIM_DATE_SOURCE)
          end

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
