# frozen_string_literal: true

require 'claims_api/lighthouse_military_address_validator'

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Rules
        module MilitaryAddressCityStateCoupling
          include ClaimsApi::LighthouseMilitaryAddressValidator
          extend ClaimsApi::LighthouseMilitaryAddressValidator

          module_function

          def call(address, source:, errors:)
            return if address.blank?
            return unless address_is_military?(address)

            city = military_city(address)
            state = military_state(address)
            valid_cities = ClaimsApi::LighthouseMilitaryAddressValidator::MILITARY_CITY_CODES
            valid_states = ClaimsApi::LighthouseMilitaryAddressValidator::MILITARY_STATE_CODES
            return if valid_cities.include?(city) && valid_states.include?(state)

            errors.add(source: "#{source}/", detail: 'Invalid city and military postal combination.')
          end
        end
      end
    end
  end
end
