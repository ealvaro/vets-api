# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers do
  subject(:helper) { dummy_class.new }

  let(:dummy_class) do
    Class.new do
      include AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers
    end
  end

  describe '#normalize_codes' do
    it 'normalizes a single string' do
      expect(helper.normalize_codes('ABC')).to eq(['ABC'])
    end

    it 'splits comma separated values' do
      expect(helper.normalize_codes('ABC, DEF')).to eq(%w[ABC DEF])
    end

    it 'handles arrays and removes blanks' do
      input = ['ABC', ' DEF ', '', nil]
      expect(helper.normalize_codes(input)).to eq(%w[ABC DEF])
    end

    it 'deduplicates values' do
      input = %w[ABC ABC DEF]
      expect(helper.normalize_codes(input)).to eq(%w[ABC DEF])
    end

    it 'flattens nested arrays and comma separated values' do
      input = ['ABC, DEF', %w[GHI ABC]]
      expect(helper.normalize_codes(input)).to eq(%w[ABC DEF GHI])
    end

    it 'splits space separated values' do
      expect(helper.normalize_codes('ABC DEF GHI')).to eq(%w[ABC DEF GHI])
    end
  end

  describe '#organizations_for' do
    it 'returns accredited organizations matching POA codes' do
      org = create(:accredited_organization, poa_code: 'ABC')
      create(:accredited_organization, poa_code: 'DEF')

      result = helper.organizations_for(['ABC'])

      expect(result).to contain_exactly(org)
    end
  end

  describe '#validate_mode!' do
    it 'does not raise for a valid mode' do
      expect { helper.validate_mode!('self_only', 'mode') }.not_to raise_error
    end

    it 'raises ArgumentError for an invalid mode' do
      expect { helper.validate_mode!('bogus', 'mode') }
        .to raise_error(ArgumentError, /Invalid mode: bogus/)
    end
  end

  describe '#set_active_reps_mode!' do
    let!(:organization) { create(:accredited_organization, poa_code: 'ABC') }

    let!(:individual1) do
      create(:accredited_individual, registration_number: 'REP1', individual_type: 'representative')
    end

    let!(:individual2) do
      create(:accredited_individual, registration_number: 'REP2', individual_type: 'representative')
    end

    let!(:accreditation1) do
      create(
        :accreditation,
        accredited_organization: organization,
        accredited_individual: individual1,
        acceptance_mode: 'any_request',
        deactivated_at: nil
      )
    end

    let!(:accreditation2) do
      create(
        :accreditation,
        accredited_organization: organization,
        accredited_individual: individual2,
        acceptance_mode: 'any_request',
        deactivated_at: nil
      )
    end

    it 'updates acceptance_mode for active accreditations' do
      org_scope = AccreditedOrganization.where(poa_code: organization.poa_code)

      updated = helper.set_active_reps_mode!(org_scope, 'self_only')

      expect(updated).to eq(2)
      expect(accreditation1.reload.acceptance_mode).to eq('self_only')
      expect(accreditation2.reload.acceptance_mode).to eq('self_only')
    end

    context 'when update count does not match expected' do
      let(:active_scope) { double('active_scope') }
      let(:joined_scope) { double('joined_scope') }
      let(:org_filtered_scope) { double('org_filtered_scope') }
      let(:where_chain) { double('where_chain') }
      let(:reps_scope) { double('reps_scope') }

      before do
        allow(Accreditation)
          .to receive(:active)
          .and_return(active_scope)

        allow(active_scope)
          .to receive(:joins)
          .with(:accredited_organization)
          .and_return(joined_scope)

        allow(joined_scope)
          .to receive(:where)
          .and_return(org_filtered_scope)

        allow(org_filtered_scope)
          .to receive(:where)
          .and_return(where_chain)

        allow(where_chain)
          .to receive(:not)
          .with(acceptance_mode: 'self_only')
          .and_return(reps_scope)

        allow(reps_scope).to receive_messages(count: 2, update_all: 1)
      end

      it 'raises MismatchError when updated count differs from expected count' do
        org_scope = AccreditedOrganization.where(poa_code: organization.poa_code)

        expect do
          helper.set_active_reps_mode!(org_scope, 'self_only')
        end.to raise_error(
          AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers::MismatchError,
          /expected 2 reps, updated 1/
        )
      end
    end
  end

  describe '#set_org_acceptance_modes!' do
    let!(:organization) do
      create(
        :accredited_organization,
        poa_code: 'ABC',
        primary_org_acceptance_mode: 'any_request',
        default_new_rep_acceptance_mode: 'any_request'
      )
    end

    it 'updates accredited org acceptance modes' do
      org_scope = AccreditedOrganization.where(poa_code: organization.poa_code)

      updated = helper.set_org_acceptance_modes!(
        org_scope, primary_mode: 'self_only', default_rep_mode: 'no_acceptance'
      )

      expect(updated).to eq(1)
      expect(organization.reload.primary_org_acceptance_mode).to eq('self_only')
      expect(organization.reload.default_new_rep_acceptance_mode).to eq('no_acceptance')
    end

    it 'is idempotent - skips orgs already at target modes' do
      org_scope = AccreditedOrganization.where(poa_code: organization.poa_code)

      updated1 = helper.set_org_acceptance_modes!(
        org_scope, primary_mode: 'self_only', default_rep_mode: 'no_acceptance'
      )
      expect(updated1).to eq(1)

      updated2 = helper.set_org_acceptance_modes!(
        org_scope, primary_mode: 'self_only', default_rep_mode: 'no_acceptance'
      )
      expect(updated2).to eq(0)
    end

    context 'when update count does not match expected' do
      let(:org_scope) { double('org_scope') }
      let(:orgs_to_update_scope) { double('orgs_to_update_scope') }

      before do
        allow(org_scope)
          .to receive(:where)
          .and_return(orgs_to_update_scope)

        allow(orgs_to_update_scope)
          .to receive_messages(count: 2, update_all: 1)
      end

      it 'raises MismatchError when updated count differs from expected count' do
        expect do
          helper.set_org_acceptance_modes!(
            org_scope,
            primary_mode: 'self_only',
            default_rep_mode: 'no_acceptance'
          )
        end.to raise_error(
          AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers::MismatchError,
          /expected 2 orgs, updated 1/
        )
      end
    end
  end

  describe '#set_specific_reps_mode!' do
    let!(:organization) { create(:accredited_organization, poa_code: 'ABC') }

    let!(:individual1) do
      create(:accredited_individual, registration_number: 'REP1', individual_type: 'representative')
    end

    let!(:individual2) do
      create(:accredited_individual, registration_number: 'REP2', individual_type: 'representative')
    end

    let!(:individual3) do
      create(:accredited_individual, registration_number: 'REP3', individual_type: 'representative')
    end

    let!(:accreditation1) do
      create(
        :accreditation,
        accredited_organization: organization,
        accredited_individual: individual1,
        acceptance_mode: 'any_request',
        deactivated_at: nil
      )
    end

    let!(:accreditation2) do
      create(
        :accreditation,
        accredited_organization: organization,
        accredited_individual: individual2,
        acceptance_mode: 'any_request',
        deactivated_at: nil
      )
    end

    let!(:accreditation3) do
      create(
        :accreditation,
        accredited_organization: organization,
        accredited_individual: individual3,
        acceptance_mode: 'any_request',
        deactivated_at: nil
      )
    end

    it 'updates acceptance mode for specified reps' do
      updated = helper.set_specific_reps_mode!('ABC', %w[REP1 REP2], 'self_only')

      expect(updated).to eq(2)
      expect(accreditation1.reload.acceptance_mode).to eq('self_only')
      expect(accreditation2.reload.acceptance_mode).to eq('self_only')
      expect(accreditation3.reload.acceptance_mode).to eq('any_request')
    end

    it 'is idempotent - skips reps already at target mode' do
      updated1 = helper.set_specific_reps_mode!('ABC', %w[REP1 REP2], 'self_only')
      expect(updated1).to eq(2)

      updated2 = helper.set_specific_reps_mode!('ABC', %w[REP1 REP2], 'self_only')
      expect(updated2).to eq(0)
    end

    context 'when update count does not match expected' do
      let(:active_scope) { double('active_scope') }
      let(:joined_scope) { double('joined_scope') }
      let(:org_filtered_scope) { double('org_filtered_scope') }
      let(:individual_filtered_scope) { double('individual_filtered_scope') }
      let(:where_chain) { double('where_chain') }
      let(:reps_scope) { double('reps_scope') }

      before do
        allow(Accreditation)
          .to receive(:active)
          .and_return(active_scope)

        allow(active_scope)
          .to receive(:joins)
          .with(:accredited_organization, :accredited_individual)
          .and_return(joined_scope)

        allow(joined_scope)
          .to receive(:where)
          .with(accredited_organizations: { poa_code: 'ABC' })
          .and_return(org_filtered_scope)

        allow(org_filtered_scope)
          .to receive(:where)
          .with(accredited_individuals: { registration_number: %w[REP1 REP2] })
          .and_return(individual_filtered_scope)

        allow(individual_filtered_scope)
          .to receive(:where)
          .and_return(where_chain)

        allow(where_chain)
          .to receive(:not)
          .with(acceptance_mode: 'self_only')
          .and_return(reps_scope)

        allow(reps_scope).to receive_messages(count: 2, update_all: 1)
      end

      it 'raises MismatchError when updated count differs from expected count' do
        expect do
          helper.set_specific_reps_mode!('ABC', %w[REP1 REP2], 'self_only')
        end.to raise_error(
          AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers::MismatchError,
          /expected 2 reps, updated 1/
        )
      end
    end
  end
end
