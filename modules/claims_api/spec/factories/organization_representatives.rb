# frozen_string_literal: true

FactoryBot.define do
  factory :claims_api_organization_representative,
          class: 'ClaimsApi::OrganizationRepresentative' do
    association :representative, factory: :claims_api_representative
    association :organization, factory: :claims_api_organization

    # join table stores these columns; set explicitly so it's not relying on AR magic
    representative_id { representative.representative_id }
    organization_poa { organization.poa }

    acceptance_mode { 'any_request' }
  end
end
