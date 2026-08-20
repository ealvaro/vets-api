# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA10272 do
  before do
    Sidekiq::Job.clear_all
  end

  let(:instance) { build(:va10272) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-10272')

  describe 'requires_authenticated_user?' do
    it 'requires an authenticated user' do
      expect(instance.requires_authenticated_user?).to be(true)
    end
  end

  describe 'retention_period' do
    it 'returns the correct period' do
      expect(instance.retention_period).to be_within(1.minute).of(60.days)
    end
  end

  describe 'after_submit' do
    let(:claim) { create(:va10272) }
    let(:user) { create(:user) }
    let!(:attachment) do
      create(:claim_evidence, guid: 'ffffffff-1111-2222-3333-444444444444', form_id: '22-10272')
    end

    it 'associates supporting documents and queues a submit claim job' do
      claim.after_submit(user)

      expect(attachment.reload.saved_claim_id).to eq(claim.id)
      expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs.size).to eq(1)
      expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs[0]['args'].first).to eq(claim.id)
      expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs[0]['args'].second).to eq(user.user_account.id)
    end
  end

  describe 'generate_benefits_intake_metadata' do
    it 'returns the right metadata' do
      expect(instance.generate_benefits_intake_metadata).to eq({
                                                                 'veteranFirstName' => 'Jane',
                                                                 'veteranLastName' => 'Smith',
                                                                 'fileNumber' => '123456789',
                                                                 'zipCode' => '20001',
                                                                 'source' => 'SavedClaim::EducationBenefits::VA10272',
                                                                 'docType' => '22-10272',
                                                                 'businessLine' => 'EDU'
                                                               })
    end
  end

  describe 'personalisation' do
    it 'returns the right values' do
      expect(instance.personalisation).to eq({
                                               first_name: 'Jane',
                                               last_name: 'Smith'
                                             })
    end
  end

  describe 'email' do
    it 'returns the right values' do
      expect(instance.email).to eq('jane@randallware.net')
    end
  end
end
