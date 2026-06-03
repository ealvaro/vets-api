# frozen_string_literal: true

module Mobile
  module V0
    module PowerOfAttorney
      class AccreditedOrganizationSerializer
        include JSONAPI::Serializer

        set_id :poa_code

        attributes :address_line1, :address_line2, :address_line3, :address_type,
                   :city, :country_name, :country_code_iso3, :province,
                   :international_postal_code, :state_code, :zip_code, :zip_suffix, :phone

        attribute :type do
          'organization'
        end

        attribute :name
      end
    end
  end
end
