# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::AccreditationSync do
  let(:rep1) { create(:accredited_individual, individual_type: 'representative') }
  let(:rep2) { create(:accredited_individual, individual_type: 'representative') }
  let(:org) { create(:accredited_organization, default_new_rep_acceptance_mode: 'any_request') }

  describe '.sync!' do
    it 'inserts missing accreditations seeded with the organization default acceptance_mode' do
      expect do
        described_class.sync!(
          individual_org_id_pairs: [[rep1.id, org.id], [rep2.id, org.id]],
          organization_ids: [org.id]
        )
      end.to change(Accreditation, :count).by(2)

      expect(Accreditation.find_by(accredited_individual_id: rep1.id,
                                   accredited_organization_id: org.id).acceptance_mode).to eq('any_request')
    end

    it "seeds acceptance_mode from the organization's no_acceptance default" do
      org.update!(default_new_rep_acceptance_mode: 'no_acceptance')

      described_class.sync!(individual_org_id_pairs: [[rep1.id, org.id]], organization_ids: [org.id])

      expect(Accreditation.find_by(accredited_individual_id: rep1.id,
                                   accredited_organization_id: org.id).acceptance_mode).to eq('no_acceptance')
    end

    it 'does not overwrite acceptance_mode on an existing accreditation' do
      create(:accreditation, accredited_individual: rep1, accredited_organization: org, acceptance_mode: 'self_only')

      expect do
        described_class.sync!(individual_org_id_pairs: [[rep1.id, org.id]], organization_ids: [org.id])
      end.not_to change(Accreditation, :count)

      expect(Accreditation.find_by(accredited_individual_id: rep1.id,
                                   accredited_organization_id: org.id).acceptance_mode).to eq('self_only')
    end

    it 'reactivates a previously deactivated pair that is present again' do
      accreditation = create(:accreditation, accredited_individual: rep1, accredited_organization: org,
                                             deactivated_at: Time.current)

      described_class.sync!(individual_org_id_pairs: [[rep1.id, org.id]], organization_ids: [org.id])

      expect(accreditation.reload.deactivated_at).to be_nil
    end

    it 'soft-deletes a pair that is no longer present for a synced organization' do
      stale = create(:accreditation, accredited_individual: rep2, accredited_organization: org)

      described_class.sync!(individual_org_id_pairs: [[rep1.id, org.id]], organization_ids: [org.id])

      expect(stale.reload.deactivated_at).to be_present
      expect(Accreditation.find_by(accredited_individual_id: rep1.id, accredited_organization_id: org.id))
        .to be_present
    end

    it 'does not touch accreditations for organizations outside the synced set' do
      other_org = create(:accredited_organization)
      untouched = create(:accreditation, accredited_individual: rep2, accredited_organization: other_org)

      described_class.sync!(individual_org_id_pairs: [[rep1.id, org.id]], organization_ids: [org.id])

      expect(untouched.reload.deactivated_at).to be_nil
    end

    it 'is a no-op when there are no pairs' do
      expect do
        described_class.sync!(individual_org_id_pairs: [], organization_ids: [org.id])
      end.not_to change(Accreditation, :count)
    end

    it 'is a no-op when there are no organization ids' do
      expect do
        described_class.sync!(individual_org_id_pairs: [[rep1.id, org.id]], organization_ids: [])
      end.not_to change(Accreditation, :count)
    end
  end
end
