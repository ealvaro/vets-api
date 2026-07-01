# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::OrganizationWithAcceptanceMode do
  subject { described_class.new(organization, acceptance_mode:) }

  let(:organization) { create(:accredited_organization, poa_code: 'ABC', can_accept_digital_poa_requests: true) }

  describe '#acceptance_mode' do
    context 'when an acceptance_mode is supplied' do
      let(:acceptance_mode) { 'any_request' }

      it 'returns the supplied mode' do
        expect(subject.acceptance_mode).to eq('any_request')
      end
    end

    context 'when no acceptance_mode is supplied' do
      let(:acceptance_mode) { nil }

      it 'defaults to no_acceptance' do
        expect(subject.acceptance_mode).to eq('no_acceptance')
      end
    end
  end

  describe 'delegation' do
    let(:acceptance_mode) { 'self_only' }

    it 'delegates other methods to the organization' do
      expect(subject.poa_code).to eq('ABC')
      expect(subject.name).to eq(organization.name)
      expect(subject.can_accept_digital_poa_requests).to be(true)
    end
  end

  describe '.acceptance_modes_for' do
    let(:individual) { create(:accredited_individual, registration_number: 'REG123') }
    let(:org_any) { create(:accredited_organization, poa_code: 'ANY') }
    let(:org_self) { create(:accredited_organization, poa_code: 'SLF') }

    it 'maps each registration_number to its { poa_code => acceptance_mode } for active accreditations' do
      create(:accreditation, accredited_individual: individual, accredited_organization: org_any,
                             acceptance_mode: 'any_request')
      create(:accreditation, accredited_individual: individual, accredited_organization: org_self,
                             acceptance_mode: 'self_only')

      expect(described_class.acceptance_modes_for([individual]))
        .to eq('REG123' => { 'ANY' => 'any_request', 'SLF' => 'self_only' })
    end

    it 'builds the lookup for multiple individuals in a single map' do
      other = create(:accredited_individual, registration_number: 'REG999')
      create(:accreditation, accredited_individual: individual, accredited_organization: org_any,
                             acceptance_mode: 'any_request')
      create(:accreditation, accredited_individual: other, accredited_organization: org_self,
                             acceptance_mode: 'self_only')

      expect(described_class.acceptance_modes_for([individual, other]))
        .to eq('REG123' => { 'ANY' => 'any_request' }, 'REG999' => { 'SLF' => 'self_only' })
    end

    it 'excludes deactivated accreditations' do
      create(:accreditation, accredited_individual: individual, accredited_organization: org_any,
                             acceptance_mode: 'any_request', deactivated_at: Time.current)

      expect(described_class.acceptance_modes_for([individual])).to eq({})
    end

    it 'returns an empty hash when no individuals have a registration number' do
      individual_without_registration = instance_double(AccreditedIndividual, registration_number: nil)

      expect(described_class.acceptance_modes_for([individual_without_registration])).to eq({})
    end
  end
end
