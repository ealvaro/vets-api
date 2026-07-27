# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'AccreditedRepresentativePortal::SetupAccreditedStagingUsers' do
  before(:all) do
    load Rails.root.join('modules', 'accredited_representative_portal', 'lib', 'tasks',
                         'setup_accredited_staging_users.rake').to_s
  end

  let(:setup) { AccreditedRepresentativePortal::SetupAccreditedStagingUsers }
  let(:result) { Hash.new(0) }
  let(:individual) { create(:accredited_individual, :representative) }

  describe '.sync_representative_accreditations!' do
    let!(:organization_a) { create(:accredited_organization, poa_code: 'AAA') }
    let!(:organization_b) { create(:accredited_organization, poa_code: 'BBB') }

    it 'creates accreditations with alternating acceptance modes' do
      setup.sync_representative_accreditations!(individual, %w[AAA BBB], result)

      modes = Accreditation.where(accredited_individual: individual)
                           .joins(:accredited_organization)
                           .order('accredited_organizations.poa_code')
                           .pluck(:acceptance_mode)

      expect(modes).to eq(%w[any_request self_only])
      expect(result[:accreditations_created_count]).to eq(2)
    end

    it 'records organizations that cannot be found' do
      setup.sync_representative_accreditations!(individual, %w[ZZZ], result)

      expect(result[:missing_org_count]).to eq(1)
      expect(Accreditation.where(accredited_individual: individual).count).to eq(0)
    end

    it 'reactivates a previously deactivated accreditation' do
      create(:accreditation,
             accredited_individual: individual,
             accredited_organization: organization_a,
             deactivated_at: Time.current)

      setup.sync_representative_accreditations!(individual, %w[AAA], result)

      expect(result[:accreditations_activated_count]).to eq(1)
      expect(
        Accreditation.find_by(accredited_individual: individual, accredited_organization: organization_a).deactivated_at
      ).to be_nil
    end

    it 'does not create duplicate accreditations on re-run' do
      2.times { setup.sync_representative_accreditations!(individual, %w[AAA BBB], Hash.new(0)) }

      expect(Accreditation.where(accredited_individual: individual).count).to eq(2)
    end

    context 'when the individual is not a representative' do
      let(:individual) { create(:accredited_individual, :attorney) }

      it 'does not create any accreditations' do
        setup.sync_representative_accreditations!(individual, %w[AAA], result)

        expect(Accreditation.where(accredited_individual: individual).count).to eq(0)
      end
    end
  end
end
