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
end
