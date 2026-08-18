# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DependentsBenefits::SchoolAttendanceApproval do
  before do
    allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/mock_form_final.pdf')
    allow_any_instance_of(DependentsBenefits::SchoolAttendanceApproval).to receive(:pdf_overflow_tracking)
    allow(Flipper).to receive(:enabled?).with(:enable_686_674_digital_pdf).and_return(false)
  end

  let(:saved_claim) { create(:student_claim) }

  describe '#to_pdf' do
    it 'does not fail' do
      expect(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_call_original
      expect { saved_claim.to_pdf }.not_to raise_error
    end
  end

  describe '#form_id' do
    it 'returns the correct form id' do
      claim = DependentsBenefits::SchoolAttendanceApproval.new(form: saved_claim.form)
      expect(claim.form_id).to eq('21-674')
    end
  end

  describe '#business_line' do
    it 'returns CMP' do
      claim = DependentsBenefits::SchoolAttendanceApproval.new(form: saved_claim.form)
      expect(claim.business_line).to eq('CMP')
    end
  end

  describe 'overflow tracking' do
    let(:user) { create(:evss_user) }
    let(:parent_claim) { create(:dependents_claim) }

    before do
      allow(StatsD).to receive(:increment)
      allow_any_instance_of(DependentsBenefits::SchoolAttendanceApproval).to receive(
        :pdf_overflow_tracking
      ).and_call_original
      user_data = DependentsBenefits::UserData.new(user, parent_claim.parsed_form)

      SavedClaimGroup.new(claim_group_guid: parent_claim.guid,
                          parent_claim_id: parent_claim.id,
                          saved_claim_id: parent_claim.id,
                          user_data: user_data.get_user_json).save!
    end

    it 'calls StatsD' do
      expect(StatsD).to receive(:increment).with('saved_claim.pdf.overflow',
                                                 tags: ['form_id:21-674', 'doctype:142']).once
      expect(Common::FileHelpers).to receive(:delete_file_if_exists).with('tmp/pdfs/mock_form_final.pdf')

      form_data = parent_claim.parsed_form
      student_data = form_data.dig('dependents_application', 'student_information').first

      expect do
        DependentsBenefits::Generators::Claim674Generator.new(form_data, parent_claim.id,
                                                              student_data).generate
      end.to change(DependentsBenefits::SchoolAttendanceApproval, :count).by(1)
    end
  end
end
