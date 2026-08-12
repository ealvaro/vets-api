# frozen_string_literal: true

module RepresentationManagement
  module AccreditedEntities
    # Nested organization result for a representative in the appoint-a-representative search. Mirrors
    # the legacy OriginalEntities::RepresentativeOrganizationSerializer shape exactly: full address and
    # a per-rep gated can_accept_digital_poa_requests, with no reps_can_accept_any_request.
    class RepresentativeOrganizationSerializer
      include JSONAPI::Serializer

      set_type :organization
      set_id :poa_code

      attributes :poa_code, :name, :address_line1, :address_line2, :address_line3, :address_type,
                 :city, :country_name, :country_code_iso3, :province, :international_postal_code, :state_code,
                 :zip_code, :zip_suffix, :phone, :lat, :long

      # Gated per-rep, matching legacy OriginalEntities::RepresentativeOrganizationSerializer via
      # OrganizationWithRepContext: the org only "accepts" for this rep when it allows digital POA
      # requests AND the rep's acceptance_mode is not no_acceptance (i.e. self_only or any_request).
      attribute :can_accept_digital_poa_requests do |object|
        object.can_accept_digital_poa_requests &&
          object.acceptance_mode != RepresentationManagement::OrganizationWithAcceptanceMode::DEFAULT_ACCEPTANCE_MODE
      end
    end
  end
end
