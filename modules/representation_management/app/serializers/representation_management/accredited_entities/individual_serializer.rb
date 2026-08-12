# frozen_string_literal: true

module RepresentationManagement
  module AccreditedEntities
    class IndividualSerializer
      include JSONAPI::Serializer

      attributes :first_name, :last_name, :full_name,
                 :address_line1,
                 :address_line2, :address_line3, :address_type,
                 :city, :country_name, :country_code_iso3, :province,
                 :international_postal_code, :state_code, :zip_code, :zip_suffix,
                 :phone, :email,
                 :individual_type

      attribute :accredited_organizations do |object, params|
        modes = (params[:acceptance_modes] || {})[object.registration_number] || {}
        organizations = object.accredited_organizations.map do |org|
          RepresentationManagement::OrganizationWithAcceptanceMode.new(
            org, acceptance_mode: modes[org.poa_code]
          )
        end
        RepresentationManagement::AccreditedEntities::RepresentativeOrganizationSerializer.new(organizations)
      end
    end
  end
end
