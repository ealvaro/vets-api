# frozen_string_literal: true

module RepresentationManagement
  class OrganizationWithRepContext < SimpleDelegator
    def initialize(organization, accepting_poas:)
      super(organization)
      @accepting_poas = accepting_poas
    end

    def can_accept_digital_poa_requests
      return false unless __getobj__.can_accept_digital_poa_requests

      @accepting_poas.include?(__getobj__.poa)
    end

    def self.accepting_poas_for(representative)
      Veteran::Service::OrganizationRepresentative.active
                                                  .where(representative_id: representative.representative_id)
                                                  .where.not(acceptance_mode: 'no_acceptance')
                                                  .pluck(:organization_poa)
                                                  .to_set
    end
  end
end
