# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::Organization, type: :model do
  before do
    allow(Flipper).to receive(:enabled?)
      .with(ClaimsApi::AccreditationTables::FLAG).and_return(true)
  end

  describe 'table mapping' do
    it 'is backed by the claims_api_organizations table' do
      expect(described_class.table_name).to eq('claims_api_organizations')
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(described_class.new(poa: '000')).to be_valid
    end

    it 'is not valid without a poa' do
      organization = described_class.new(poa: nil)
      expect(organization).not_to be_valid
      expect(organization.errors[:poa]).to be_present
    end
  end

  describe 'enums' do
    describe 'primary_org_acceptance_mode' do
      it 'accepts valid values' do
        org = described_class.new(poa: '000')
        expect { org.primary_any_request! }.not_to raise_error
        expect { org.primary_self_only! }.not_to raise_error
        expect { org.primary_no_acceptance! }.not_to raise_error
      end

      it 'has default value of no_acceptance' do
        org = described_class.new(poa: '000')
        expect(org.primary_org_acceptance_mode).to eq('no_acceptance')
      end

      it 'provides predicate methods' do
        org = described_class.create!(poa: 'ABC', primary_org_acceptance_mode: 'any_request')
        expect(org.primary_any_request?).to be true
        expect(org.primary_self_only?).to be false
        expect(org.primary_no_acceptance?).to be false
      end
    end

    describe 'default_new_rep_acceptance_mode' do
      it 'accepts valid values' do
        org = described_class.new(poa: '000')
        expect { org.default_rep_any_request! }.not_to raise_error
        expect { org.default_rep_self_only! }.not_to raise_error
        expect { org.default_rep_no_acceptance! }.not_to raise_error
      end

      it 'has default value of no_acceptance' do
        org = described_class.new(poa: '000')
        expect(org.default_new_rep_acceptance_mode).to eq('no_acceptance')
      end

      it 'provides predicate methods' do
        org = described_class.create!(poa: 'DEF', default_new_rep_acceptance_mode: 'self_only')
        expect(org.default_rep_any_request?).to be false
        expect(org.default_rep_self_only?).to be true
        expect(org.default_rep_no_acceptance?).to be false
      end
    end
  end

  describe 'associations' do
    it 'has many organization_representatives' do
      assoc = described_class.reflect_on_association(:organization_representatives)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.class_name).to eq('ClaimsApi::OrganizationRepresentative')
      expect(assoc.foreign_key.to_s).to eq('organization_poa')
      expect(assoc.options[:primary_key].to_s).to eq('poa')
    end

    it 'has many representatives through organization_representatives' do
      assoc = described_class.reflect_on_association(:representatives)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:through]).to eq(:organization_representatives)
      expect(assoc.options[:source]).to eq(:representative)
    end
  end

  describe 'integration' do
    it 'returns representatives through the join table' do
      org = create(:claims_api_organization, poa: 'ABC', name: 'Test Org')
      rep = create(:claims_api_representative, representative_id: 'REP123', poa_codes: ['ABC'])
      create(:claims_api_organization_representative,
             organization: org, representative: rep, acceptance_mode: 'any_request')

      expect(org.representatives).to contain_exactly(rep)
    end
  end
end
