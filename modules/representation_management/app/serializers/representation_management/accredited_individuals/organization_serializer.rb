# frozen_string_literal: true

module RepresentationManagement
  module AccreditedIndividuals
    class OrganizationSerializer
      include JSONAPI::Serializer

      attributes :poa_code, :name, :address_line1, :address_line2, :address_line3, :address_type,
                 :city, :country_name, :country_code_iso3, :province, :international_postal_code, :state_code,
                 :zip_code, :zip_suffix, :phone, :lat, :long, :can_accept_digital_poa_requests

      # acceptance_mode is the per-(rep, org) mode supplied by OrganizationWithAcceptanceMode.
      # Bare organizations (no rep context) default to no_acceptance.
      attribute :acceptance_mode do |object|
        if object.respond_to?(:acceptance_mode)
          object.acceptance_mode
        else
          RepresentationManagement::OrganizationWithAcceptanceMode::DEFAULT_ACCEPTANCE_MODE
        end
      end
    end
  end
end
