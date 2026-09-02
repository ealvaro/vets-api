# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Sections
        class ClaimInformation
          def initialize(payload, brd_lookup:)
            @payload = payload || []
            @brd_lookup = brd_lookup
          end

          def validate
            errors = Errors.new(base_source: '/claimInformation')
            # nil / non-object array elements guarded by JSON Schema (v3/526.json claimInformation items).
            @payload.each_with_index do |item, idx|
              Fields::YearMonthDate.call(
                item['approximateDate'],
                source: "/#{idx}/approximateDate",
                errors:
              )
              Rules::ClassificationCodeIsActive.call(
                item['classificationCode'],
                source: "/#{idx}/classificationCode",
                errors:,
                brd_lookup: @brd_lookup
              )
              Fields::FlexiblePartialDate.call(
                item.dig('serviceRelevanceExplanation', 'approximateDate'),
                source: "/#{idx}/serviceRelevanceExplanation/approximateDate",
                errors:
              )
            end
            errors
          end
        end
      end
    end
  end
end
