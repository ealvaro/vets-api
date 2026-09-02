# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Rules
        module ClassificationCodeIsActive
          module_function

          def call(value, source:, errors:, brd_lookup:)
            return if value.nil?

            code = Integer(value, exception: false)

            if code.nil? || brd_lookup.active_classification_ids.exclude?(code)
              errors.add(
                source:,
                detail: 'classificationCode must match an active code returned from the /disabilities endpoint ' \
                        'of the Benefits Reference Data API.'
              )
              return
            end

            end_date = brd_lookup.classification_end_date_for(code)
            return if end_date.nil? || end_date >= Date.current

            errors.add(source:, detail: 'classificationCode is no longer active.')
          end
        end
      end
    end
  end
end
