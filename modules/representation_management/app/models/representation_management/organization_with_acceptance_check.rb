# frozen_string_literal: true

module RepresentationManagement
  class OrganizationWithAcceptanceCheck < SimpleDelegator
    def initialize(organization, any_request_poas:)
      super(organization)
      @any_request_poas = any_request_poas
    end

    def reps_can_accept_any_request
      @any_request_poas.include?(__getobj__.poa)
    end

    def self.any_request_poas_for(organizations)
      poas = organizations.map(&:poa)
      Veteran::Service::OrganizationRepresentative.active
                                                  .where(organization_poa: poas, acceptance_mode: 'any_request')
                                                  .distinct
                                                  .pluck(:organization_poa)
                                                  .to_set
    end
  end
end
