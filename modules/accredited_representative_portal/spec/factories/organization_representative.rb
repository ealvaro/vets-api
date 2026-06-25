# frozen_string_literal: true

FactoryBot.define do
  factory :organization_representative, class: 'Veteran::Service::OrganizationRepresentative' do
    representative_id { Faker::Number.number }
    organization_poa { 'YHZ' }
    acceptance_mode { 'self_only' }
  end
end
