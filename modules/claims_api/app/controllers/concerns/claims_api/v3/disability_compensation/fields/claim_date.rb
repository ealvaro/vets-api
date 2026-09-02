# frozen_string_literal: true

require 'claims_api/common/exceptions/lighthouse/json_form_validation_error'

# Field::ClaimDate validates the claim date format is valid and
# falls back to Date.current if not present
module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        class ClaimDate
          # claim_date is used by BDD and 180-day checks downstream,
          # so raising immediately on invalid date prevents downstream errors
          def initialize(raw_field, source:)
            @raw_field = raw_field.presence ? raw_field : Date.current
            @source = source
          end

          # like other Fields::*, #validate reports validity (raises here, rather
          # than adding to an errors collector) and its return value is unused.
          # Use #parse to get the actual parsed date, mirroring Fields::FullDate.
          def validate
            format_field_to_date
            nil
          end

          # returns the claim_date
          def parse
            format_field_to_date
          end

          private

          def format_field_to_date
            Date.iso8601(@raw_field.to_s)
          rescue ArgumentError, TypeError
            # If the date is invalid, raise immediately to prevent downstream errors
            raise ::ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError, [
              {
                title: 'Unprocessable Entity',
                status: '422',
                source: @source,
                detail: "#{@raw_field} is not a valid date."
              }
            ]
          end
        end
      end
    end
  end
end
