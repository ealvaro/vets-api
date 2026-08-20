# frozen_string_literal: true

module RepresentationManagement
  module AccreditedEntities
    class IndividualSerializer
      include JSONAPI::Serializer

      # AccreditedIndividual uses a UUID primary key, but the appoint-a-representative flow
      # (FE submit -> representative_id -> accredited_individual_registration_number) expects
      # the entity id to be the registration number, matching the legacy
      # Veteran::Service::Representative contract (primary_key = :representative_id) and the
      # OrganizationSerializer's `set_id :poa_code`.
      set_id :registration_number

      attributes :first_name, :last_name, :full_name,
                 :address_line1,
                 :address_line2, :address_line3, :address_type,
                 :city, :country_name, :country_code_iso3, :province,
                 :international_postal_code, :state_code, :zip_code, :zip_suffix,
                 :phone, :email,
                 :individual_type

      attribute :accredited_organizations do |object, params|
        modes = (params[:acceptance_modes] || {})[object.registration_number] || {}
        organizations = object.active_accredited_organizations.map do |org|
          RepresentationManagement::OrganizationWithAcceptanceMode.new(
            org, acceptance_mode: modes[org.poa_code]
          )
        end
        RepresentationManagement::AccreditedEntities::RepresentativeOrganizationSerializer.new(organizations)
      end
    end
  end
end
