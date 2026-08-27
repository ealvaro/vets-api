# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Fields
        class Address
          def initialize(value, source:)
            @value = value || {}
            @source = source
          end

          def validate(errors:, valid_countries:)
            return if @value.empty?

            validate_country(errors:, valid_countries:)
            validate_usa_state(errors:)
            validate_usa_zip(errors:)
            validate_no_intl_postal_when_usa(errors:)
            validate_intl_postal_when_not_usa(errors:)
          end

          private

          def validate_country(errors:, valid_countries:)
            return if valid_countries.include?(@value['country'])

            errors.add(source: "#{@source}/country", detail: 'The country provided is not valid.')
          end

          def validate_usa_state(errors:)
            return unless usa?
            return if @value['state'].present?

            errors.add(source: "#{@source}/state", detail: 'The state is required if the country is USA.')
          end

          def validate_usa_zip(errors:)
            return unless usa?
            return if @value['zipFirstFive'].present?

            errors.add(source: "#{@source}/zipFirstFive",
                       detail: 'The zipFirstFive is required if the country is USA.')
          end

          def validate_no_intl_postal_when_usa(errors:)
            return unless usa?
            return if @value['internationalPostalCode'].blank?

            errors.add(source: "#{@source}/internationalPostalCode",
                       detail: 'The internationalPostalCode should not be provided if the country is USA.')
          end

          def validate_intl_postal_when_not_usa(errors:)
            return if usa?
            return if @value['internationalPostalCode'].present?

            errors.add(source: "#{@source}/internationalPostalCode",
                       detail: 'The internationalPostalCode is required if the country is not USA (international).')
          end

          def usa?
            @value['country'] == 'USA'
          end
        end
      end
    end
  end
end
