# frozen_string_literal: true

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Sections
        class VeteranIdentification
          def initialize(payload, valid_countries:)
            @payload = payload || {}
            @valid_countries = valid_countries
          end

          def validate
            errors = Errors.new(base_source: '/veteranIdentification')
            return errors.messages if @payload.empty?

            Fields::Address.new(
              @payload['mailingAddress'],
              source: '/mailingAddress'
            ).validate(errors:, valid_countries: @valid_countries)

            Fields::ServiceNumber.new(
              @payload['serviceNumber'],
              source: '/serviceNumber'
            ).validate(errors:)

            errors.messages
          end
        end
      end
    end
  end
end
