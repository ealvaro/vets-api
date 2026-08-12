# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::AccreditedOrganizationWithAcceptanceCheck do
  subject { described_class.new(organization, any_request_poas:) }

  let(:organization) { create(:accredited_organization, poa_code: 'ABC', can_accept_digital_poa_requests: true) }
  let(:any_request_poas) { described_class.any_request_poas_for([organization]) }

  describe '#can_accept_digital_poa_requests' do
    it 'delegates to the underlying organization' do
      expect(subject.can_accept_digital_poa_requests).to eq(organization.can_accept_digital_poa_requests)
    end
  end

  describe '#reps_can_accept_any_request' do
    let(:individual) { create(:accredited_individual) }

    context 'when an active accreditation has acceptance_mode any_request' do
      before do
        create(:accreditation,
               accredited_individual: individual,
               accredited_organization: organization,
               acceptance_mode: 'any_request')
      end

      it 'returns true' do
        expect(subject.reps_can_accept_any_request).to be true
      end
    end

    context 'when an active accreditation has acceptance_mode self_only' do
      before do
        create(:accreditation,
               accredited_individual: individual,
               accredited_organization: organization,
               acceptance_mode: 'self_only')
      end

      it 'returns false' do
        expect(subject.reps_can_accept_any_request).to be false
      end
    end

    context 'when no accreditation records exist' do
      it 'returns false' do
        expect(subject.reps_can_accept_any_request).to be false
      end
    end

    context 'when the only any_request accreditation is deactivated' do
      before do
        create(:accreditation,
               accredited_individual: individual,
               accredited_organization: organization,
               acceptance_mode: 'any_request',
               deactivated_at: Time.current)
      end

      it 'returns false' do
        expect(subject.reps_can_accept_any_request).to be false
      end
    end
  end

  describe '.any_request_poas_for' do
    let(:individual) { create(:accredited_individual) }

    it 'returns a set of poa_codes with active any_request accreditations' do
      create(:accreditation,
             accredited_individual: individual,
             accredited_organization: organization,
             acceptance_mode: 'any_request')

      expect(described_class.any_request_poas_for([organization])).to eq(Set['ABC'])
    end

    it 'excludes poa_codes whose only any_request accreditation is deactivated' do
      create(:accreditation,
             accredited_individual: individual,
             accredited_organization: organization,
             acceptance_mode: 'any_request',
             deactivated_at: Time.current)

      expect(described_class.any_request_poas_for([organization])).to eq(Set.new)
    end
  end
end
