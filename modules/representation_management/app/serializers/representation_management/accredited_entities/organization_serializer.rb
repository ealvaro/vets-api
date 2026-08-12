# frozen_string_literal: true

module RepresentationManagement
  module AccreditedEntities
    # Top-level organization result for the appoint-a-representative search. Mirrors the legacy
    # OriginalEntities::OrganizationSerializer shape exactly: full address plus the raw
    # can_accept_digital_poa_requests flag and reps_can_accept_any_request (supplied by
    # AccreditedOrganizationWithAcceptanceCheck).
    class OrganizationSerializer
      include JSONAPI::Serializer

      set_type :organization
      set_id :poa_code

      attributes :poa_code, :name, :address_line1, :address_line2, :address_line3, :address_type,
                 :city, :country_name, :country_code_iso3, :province, :international_postal_code, :state_code,
                 :zip_code, :zip_suffix, :phone, :lat, :long, :can_accept_digital_poa_requests,
                 :reps_can_accept_any_request
    end
  end
end
