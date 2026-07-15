# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA0989 do
  let(:instance) { build(:va0989) }

  before do
    Sidekiq::Job.clear_all
  end

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-0989')

  describe 'retention_period' do
    it 'returns the correct period' do
      expect(instance.retention_period).to be_within(1.minute).of(60.days)
    end
  end

  describe 'after_submit' do
    let(:claim) { create(:va0989) }
    let(:user) { create(:user) }

    it 'does not queue a Benefits Intake upload job (0989 uses the nightly spool file)' do
      claim.after_submit(user)
      expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs).to be_empty
    end
  end
end
