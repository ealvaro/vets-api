# frozen_string_literal: true

module RepresentationManagement
  # Accredited-side analog of OrganizationWithAcceptanceCheck. Wraps a top-level
  # AccreditedOrganization search result and tags it with reps_can_accept_any_request, mirroring the
  # legacy behavior so the appoint-a-representative flow serializes the same shape regardless of which
  # data source (legacy Veteran::Service::* or AccreditedX) is active.
  class AccreditedOrganizationWithAcceptanceCheck < SimpleDelegator
    def initialize(organization, any_request_poas:)
      super(organization)
      @any_request_poas = any_request_poas
    end

    def reps_can_accept_any_request
      @any_request_poas.include?(__getobj__.poa_code)
    end

    # Builds the set of poa_codes that have at least one active representative willing to accept any
    # request, in a single query so serializing a page of results doesn't trigger a per-org query.
    #
    # @return [Set<String>]
    def self.any_request_poas_for(organizations)
      poa_codes = organizations.map(&:poa_code)
      Accreditation.active
                   .any_request
                   .for_organization_poa_codes(poa_codes)
                   .distinct
                   .pluck('accredited_organizations.poa_code')
                   .to_set
    end
  end
end
