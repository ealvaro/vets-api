# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Accreditation, type: :model do
  describe 'validations' do
    subject { build(:accreditation) }

    it { is_expected.to belong_to(:accredited_individual) }
    it { is_expected.to belong_to(:accredited_organization) }

    it {
      expect(subject).to validate_uniqueness_of(:accredited_organization_id)
        .scoped_to(:accredited_individual_id)
        .ignoring_case_sensitivity
    }
  end

  describe 'acceptance_mode enum' do
    it 'exposes the expected values' do
      expect(described_class.acceptance_modes).to eq(
        'any_request' => 'any_request',
        'self_only' => 'self_only',
        'no_acceptance' => 'no_acceptance'
      )
    end

    it 'defaults to no_acceptance' do
      expect(build(:accreditation).acceptance_mode).to eq('no_acceptance')
    end
  end

  describe 'scopes' do
    let!(:active_accreditation) { create(:accreditation) }
    let!(:deactivated_accreditation) { create(:accreditation, deactivated_at: Time.current) }

    describe '.active' do
      it 'returns only accreditations without a deactivated_at' do
        expect(described_class.active).to include(active_accreditation)
        expect(described_class.active).not_to include(deactivated_accreditation)
      end
    end

    describe '.deactivated' do
      it 'returns only accreditations with a deactivated_at' do
        expect(described_class.deactivated).to include(deactivated_accreditation)
        expect(described_class.deactivated).not_to include(active_accreditation)
      end
    end

    describe '.for_organization_poa_codes' do
      it 'filters by the joined organization poa_code' do
        org = create(:accredited_organization, poa_code: 'ABC')
        accreditation = create(:accreditation, accredited_organization: org)

        result = described_class.for_organization_poa_codes('ABC')

        expect(result).to include(accreditation)
        expect(result).not_to include(active_accreditation)
      end
    end

    describe '.for_registration_numbers' do
      it 'filters by the joined individual registration_number' do
        individual = create(:accredited_individual, registration_number: '12345')
        accreditation = create(:accreditation, accredited_individual: individual)

        result = described_class.for_registration_numbers('12345')

        expect(result).to include(accreditation)
        expect(result).not_to include(active_accreditation)
      end
    end
  end

  describe 'activation lifecycle' do
    describe '#deactivate!' do
      it 'sets deactivated_at' do
        accreditation = create(:accreditation)

        accreditation.deactivate!

        expect(accreditation.reload.deactivated_at).to be_present
      end
    end

    describe '#activate!' do
      it 'clears deactivated_at' do
        accreditation = create(:accreditation, deactivated_at: Time.current)

        accreditation.activate!

        expect(accreditation.reload.deactivated_at).to be_nil
      end

      it 'is a no-op when already active' do
        accreditation = create(:accreditation)

        expect(accreditation.activate!).to be(true)
        expect(accreditation.reload.deactivated_at).to be_nil
      end
    end

    describe '.deactivate!' do
      it 'deactivates the given ids and returns the count' do
        a1 = create(:accreditation)
        a2 = create(:accreditation)

        count = described_class.deactivate!([a1.id, a2.id])

        expect(count).to eq(2)
        expect(a1.reload.deactivated_at).to be_present
        expect(a2.reload.deactivated_at).to be_present
      end

      it 'returns 0 for blank input' do
        expect(described_class.deactivate!([])).to eq(0)
        expect(described_class.deactivate!(nil)).to eq(0)
      end
    end
  end
end
