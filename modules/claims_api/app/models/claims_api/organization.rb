# frozen_string_literal: true

module ClaimsApi
  class Organization < ApplicationRecord
    self.table_name = 'claims_api_organizations'
    self.primary_key = :poa

    ACCEPTANCE_MODES = %w[any_request self_only no_acceptance].freeze

    enum :primary_org_acceptance_mode, {
      any_request: 'any_request',
      self_only: 'self_only',
      no_acceptance: 'no_acceptance'
    }, prefix: :primary, default: 'no_acceptance'

    enum :default_new_rep_acceptance_mode, {
      any_request: 'any_request',
      self_only: 'self_only',
      no_acceptance: 'no_acceptance'
    }, prefix: :default_rep, default: 'no_acceptance'

    validates :poa, presence: true
    has_many :organization_representatives,
             class_name: 'ClaimsApi::OrganizationRepresentative',
             foreign_key: :organization_poa,
             primary_key: :poa,
             inverse_of: :organization,
             dependent: :destroy

    has_many :representatives,
             through: :organization_representatives,
             source: :representative

    #
    # Compares org's current info with new data to detect changes in address.
    # @param org_data [Hash] New data with :address keys for comparison.
    #
    # @return [Hash] Hash with "address_changed" keys as a boolean.
    def diff(org_data)
      { 'address_changed' => address_changed?(org_data) }
    end

    private

    #
    # Checks if the org's address has changed compared to a new address hash.
    # @param other_address [Hash] New address data with keys for address components and state code.
    #
    # @return [Boolean] True if current address differs from `other_address`, false otherwise.
    def address_changed?(org_data)
      address = [address_line1, address_line2, address_line3, city, zip_code, zip_suffix, state_code].join(' ')
      other_address = org_data[:address]
                      .values_at(:address_line1, :address_line2, :address_line3, :city, :zip_code5, :zip_code4)
                      .push(org_data.dig(:address, :state_province, :code))
                      .join(' ')
      address != other_address
    end
  end
end
