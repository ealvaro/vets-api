# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DependentsBenefits::PrimaryDependencyClaim do
  before do
    allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/mock_form_final.pdf')
    allow_any_instance_of(DependentsBenefits::PrimaryDependencyClaim).to receive(:pdf_overflow_tracking)
  end

  let(:saved_claim) { create(:dependents_claim) }

  describe '#form_id' do
    it 'returns the correct form id' do
      claim = DependentsBenefits::PrimaryDependencyClaim.new(form: saved_claim.form)
      claim.save!(validate: false)
      expect(claim.form_id).to eq('686C-674')
    end
  end

  describe '#process_attachments!' do
    let(:attachments) do
      { 'dependents_application' => {
        'child_supporting_documents' => [{
          'confirmation_code' => 'TEST'
        }]
      } }
    end
    let(:relations) { instance_double(ActiveRecord::Relation) }

    it 'links the attachments' do
      allow(saved_claim).to receive(:parsed_form).and_return(attachments)

      expect(PersistentAttachment).to receive(:where).with(guid: ['TEST']).and_return(relations)
      expect(relations).to receive(:find_each)

      saved_claim.process_attachments!
    end
  end

  describe 'create metrics' do
    before do
      allow(StatsD).to receive(:increment)
    end

    let(:claim) { described_class.new(form: form_data) }
    let(:tags) { ["form_id:#{claim.form_id}", "doctype:#{claim.document_type}"] }

    context 'with a combined 686+674 form' do
      let(:form_data) { build(:dependents_claim).form }

      it 'increments the correct metric' do
        claim.save!
        expect(claim.submittable_686?).to be(true)
        expect(claim.submittable_674?).to be(true)
        expect(StatsD).to have_received(:increment).with('saved_claim.create.dependents_686_674', tags:)
      end
    end

    context 'with a 686 only form' do
      let(:form_data) { build(:add_remove_dependents_claim).form }

      it 'increments the correct metric' do
        claim.save!
        expect(claim.submittable_686?).to be(true)
        expect(claim.submittable_674?).to be(false)
        expect(StatsD).to have_received(:increment).with('saved_claim.create.dependents_686_only', tags:)
      end
    end

    context 'with a 674 only form' do
      let(:form_data) { build(:student_claim).form }

      it 'increments the correct metric' do
        claim.save!
        expect(claim.submittable_686?).to be(false)
        expect(claim.submittable_674?).to be(true)
        expect(StatsD).to have_received(:increment).with('saved_claim.create.dependents_674_only', tags:)
      end
    end
  end

  describe '#pdf_overflow_tracking' do
    it 'does nothing' do
      claim = described_class.new(form: saved_claim.form)

      allow(claim).to receive(:to_pdf)
      claim.save!
      expect(claim).not_to have_received(:to_pdf)
    end
  end
end
