# frozen_string_literal: true

module RepresentationManagement
  # Adapter for Veteran::Service::Organization to make it compatible with AccreditedOrganization serializer
  class AccreditedOrganizationAdapter
    attr_reader :organization

    delegate :id, :name, :address_type, :address_line1, :address_line2, :address_line3, :phone, :city,
             :state, :state_code, :province, :country_name, :country_code_iso3, :zip_code, :zip_suffix,
             :international_postal_code, :lat, :long, :can_accept_digital_poa_requests,
             to: :organization

    def initialize(organization)
      @organization = organization
    end

    def poa_code
      organization.poa
    end

    # Support ActiveRecord-style .model_name for serializers
    def self.model_name
      AccreditedOrganization.model_name
    end
  end
end
