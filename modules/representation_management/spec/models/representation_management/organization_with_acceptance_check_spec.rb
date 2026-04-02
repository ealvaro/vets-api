# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::OrganizationWithAcceptanceCheck do
  subject { described_class.new(organization, any_request_poas:) }

  let(:organization) { create(:organization, poa: 'ABC', can_accept_digital_poa_requests: true) }
  let(:any_request_poas) { described_class.any_request_poas_for([organization]) }

  describe '#can_accept_digital_poa_requests' do
    it 'delegates to the underlying organization' do
      expect(subject.can_accept_digital_poa_requests).to eq(organization.can_accept_digital_poa_requests)
    end
  end

  describe '#reps_can_accept_any_request' do
    let(:representative) { create(:representative, representative_id: '12345') }

    context 'when an active organization_representative has acceptance_mode any_request' do
      before do
        create(:veteran_organization_representative,
               representative:,
               organization:,
               acceptance_mode: 'any_request')
      end

      it 'returns true' do
        expect(subject.reps_can_accept_any_request).to be true
      end
    end

    context 'when an active organization_representative has acceptance_mode self_only' do
      before do
        create(:veteran_organization_representative,
               representative:,
               organization:,
               acceptance_mode: 'self_only')
      end

      it 'returns false' do
        expect(subject.reps_can_accept_any_request).to be false
      end
    end

    context 'when no organization_representative records exist' do
      it 'returns false' do
        expect(subject.reps_can_accept_any_request).to be false
      end
    end

    context 'when the only any_request organization_representative is deactivated' do
      before do
        create(:veteran_organization_representative,
               representative:,
               organization:,
               acceptance_mode: 'any_request',
               deactivated_at: Time.current)
      end

      it 'returns false' do
        expect(subject.reps_can_accept_any_request).to be false
      end
    end
  end

  describe '.any_request_poas_for' do
    let(:representative) { create(:representative, representative_id: '12345') }

    it 'returns a set of POAs with active any_request reps' do
      create(:veteran_organization_representative,
             representative:,
             organization:,
             acceptance_mode: 'any_request')

      result = described_class.any_request_poas_for([organization])
      expect(result).to be_a(Set)
      expect(result).to include('ABC')
    end

    it 'excludes self_only reps' do
      create(:veteran_organization_representative,
             representative:,
             organization:,
             acceptance_mode: 'self_only')

      result = described_class.any_request_poas_for([organization])
      expect(result).not_to include('ABC')
    end

    it 'excludes no_acceptance reps' do
      create(:veteran_organization_representative,
             representative:,
             organization:,
             acceptance_mode: 'no_acceptance')

      result = described_class.any_request_poas_for([organization])
      expect(result).not_to include('ABC')
    end

    it 'excludes deactivated reps' do
      create(:veteran_organization_representative,
             representative:,
             organization:,
             acceptance_mode: 'any_request',
             deactivated_at: Time.current)

      result = described_class.any_request_poas_for([organization])
      expect(result).not_to include('ABC')
    end
  end

  it 'delegates other methods to the organization' do
    expect(subject.poa).to eq('ABC')
    expect(subject.name).to eq(organization.name)
  end
end
