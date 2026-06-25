# frozen_string_literal: true

module Mobile
  module V0
    ##
    # JSONAPI serializer for a Veteran's immunization records in the mobile (v0)
    # response shape. Exposes vaccine attributes (CVX code, dose, manufacturer,
    # etc.) and a related link to the administering location.
    #
    class ImmunizationSerializer
      include JSONAPI::Serializer

      BASE_URL = "#{Settings.hostname}/mobile/v0/health/locations/".freeze

      attributes :cvx_code,
                 :date,
                 :dose_number,
                 :dose_series,
                 :group_name,
                 :manufacturer,
                 :note,
                 :reaction,
                 :short_description

      has_one :location, links: {
        related: lambda { |object|
          object.location_id.nil? ? nil : BASE_URL + object.location_id
        }
      }
    end
  end
end
