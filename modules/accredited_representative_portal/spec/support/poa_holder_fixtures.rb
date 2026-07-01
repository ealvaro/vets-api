# frozen_string_literal: true

# Shared fixtures for exercising the legacy Veteran::Service::* path and the AccreditedX path
# of the Accredited Representative Portal migration behind the same assertions.
#
# Each builder method has one legacy and one AccreditedX implementation that produce equivalent
# domain data (registrations/orgs/acceptance links), so specs can `include_examples` once and run
# them under both the "with legacy poa holders" and "with accredited poa holders" contexts.
module AccreditedRepresentativePortal
  module LegacyPoaHolderFixtures
    USER_TYPES = { attorney: 'attorney', claims_agent: 'claim_agents',
                   vso: 'veteran_service_officer' }.freeze

    def create_holder_registration(type:, registration_number:, poa_codes: [], email: nil, # rubocop:disable Metrics/ParameterLists
                                   first_name: 'Bob', last_name: 'Law')
      attrs = {
        user_types: [USER_TYPES.fetch(type)],
        representative_id: registration_number,
        email:,
        first_name:,
        last_name:
      }
      # Let the factory supply a valid default when no codes are given (the model requires poa_codes).
      attrs[:poa_codes] = poa_codes if poa_codes.any?
      create(:representative, **attrs)
    end

    def create_holder_organization(poa_code:, name:, can_accept: false)
      create(:organization, poa: poa_code, name:, can_accept_digital_poa_requests: can_accept)
    end

    def create_holder_acceptance(registration_number:, poa_code:, acceptance_mode:, active: true)
      create(:veteran_organization_representative,
             representative: Veteran::Service::Representative.find_by(representative_id: registration_number),
             organization: Veteran::Service::Organization.find_by(poa: poa_code),
             acceptance_mode:,
             deactivated_at: active ? nil : Time.current)
    end
  end

  module AccreditedPoaHolderFixtures
    INDIVIDUAL_TYPES = { attorney: 'attorney', claims_agent: 'claims_agent',
                         vso: 'representative' }.freeze

    def create_holder_registration(type:, registration_number:, poa_codes: [], email: nil, # rubocop:disable Metrics/ParameterLists
                                   first_name: 'Bob', last_name: 'Law')
      attrs = {
        individual_type: INDIVIDUAL_TYPES.fetch(type),
        registration_number:,
        email:,
        first_name:,
        last_name:,
        full_name: "#{first_name} #{last_name}"
      }
      # Attorneys/claims agents carry their poa_code directly; a VSO rep's orgs come via accreditations.
      attrs[:poa_code] = poa_codes.first if type != :vso && poa_codes.any?
      create(:accredited_individual, **attrs)
    end

    def create_holder_organization(poa_code:, name:, can_accept: false)
      create(:accredited_organization, poa_code:, name:, can_accept_digital_poa_requests: can_accept)
    end

    def create_holder_acceptance(registration_number:, poa_code:, acceptance_mode:, active: true)
      create(:accreditation,
             accredited_individual: AccreditedIndividual.find_by(registration_number:),
             accredited_organization: AccreditedOrganization.find_by(poa_code:),
             acceptance_mode:,
             deactivated_at: active ? nil : Time.current)
    end
  end
end

RSpec.shared_context 'with legacy poa holders' do
  before do
    allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(false)
  end

  include AccreditedRepresentativePortal::LegacyPoaHolderFixtures
end

RSpec.shared_context 'with accredited poa holders' do
  before do
    allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(true)
  end

  include AccreditedRepresentativePortal::AccreditedPoaHolderFixtures
end
