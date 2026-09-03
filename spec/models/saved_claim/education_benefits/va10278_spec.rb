# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA10278 do
  before do
    Sidekiq::Job.clear_all
  end

  let(:instance) { build(:va10278) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-10278')

  describe 'retention_period' do
    it 'returns the correct period' do
      expect(instance.retention_period).to be_within(1.minute).of(60.days)
    end
  end

  describe '#to_pdf' do
    context 'when vsp_environment is production' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('production')
        allow(Rails.env).to receive_messages(development?: false, test?: false)
      end

      it 'falls back to the default to_pdf without extras_redesign options' do
        expect(PdfFill::Filler).to receive(:fill_form).with(instance, 'abc')

        instance.to_pdf('abc')
      end
    end

    context 'when vsp_environment is staging' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('staging')
        allow(Rails.env).to receive_messages(development?: false, test?: false)
      end

      it 'uses extras_redesign fill_options' do
        expect(PdfFill::Filler).to receive(:fill_form).with(
          instance, 'abc', hash_including(extras_redesign: true)
        )

        instance.to_pdf('abc')
      end
    end
  end

  describe 'after_submit' do
    let(:claim) { create(:va10278) }
    let(:user) { create(:user) }

    it 'queues up a submit claim job' do
      claim.after_submit(user)
      expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs.size).to eq(1)
      expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs[0]['args'].first).to eq(claim.id)
      expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs[0]['args'].second).to eq(user.user_account.id)
    end

    context 'with a nil user' do
      let(:user) { nil }

      it 'queues up a submit claim job, but without an account uuid' do
        claim.after_submit(user)
        expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs.size).to eq(1)
        expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs[0]['args'].first).to eq(claim.id)
        expect(EducationForm::SubmitEducationBenefitsClaimJob.jobs[0]['args'].second).to be_nil
      end
    end
  end

  describe 'generate_benefits_intake_metadata' do
    it 'returns the right metadata' do
      expect(instance.generate_benefits_intake_metadata).to eq({
                                                                 'veteranFirstName' => 'John',
                                                                 'veteranLastName' => 'Doe',
                                                                 'fileNumber' => '987654321',
                                                                 'zipCode' => '12345',
                                                                 'source' => 'SavedClaim::EducationBenefits::VA10278',
                                                                 'docType' => '22-10278',
                                                                 'businessLine' => 'EDU'
                                                               })
    end
  end

  describe 'personalisation' do
    it 'returns the right values' do
      expect(instance.personalisation).to eq({
                                               first_name: 'John',
                                               last_name: 'Doe'
                                             })
    end
  end

  describe 'email' do
    it 'returns the right values' do
      expect(instance.email).to eq('john.doe@example.com')
    end
  end
end
