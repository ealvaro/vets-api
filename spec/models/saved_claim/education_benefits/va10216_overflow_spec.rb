# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/filler'

# Tests the ExtrasGeneratorV2 overflow page wired up via VA10216#to_pdf's extras_redesign
# fill_options (see lib/pdf_fill/forms/va2210216.rb's QUESTION_KEY/SECTIONS/START_PAGE).
describe SavedClaim::EducationBenefits::VA10216 do
  before do
    allow(Flipper).to receive(:enabled?).with(:saved_claim_pdf_overflow_tracking).and_return(false)
  end

  after do
    FileUtils.rm_rf('tmp/pdfs')
  end

  describe '#to_pdf' do
    context 'when the institution name and school official name/title/signature overflow' do
      let(:saved_claim) { create(:va10216_overflow) }

      it 'renders the overflow page with all four fields using ExtrasGeneratorV2' do
        the_extras_generator = nil
        expect(PdfFill::Filler).to receive(:combine_extras).once do |old_file_path, extras_generator|
          the_extras_generator = extras_generator
          old_file_path
        end

        saved_claim.to_pdf('abc')

        questions = the_extras_generator.instance_variable_get(:@questions).compact
        expect(questions.keys).to contain_exactly('1', '8', '9', '10')

        extras_path = the_extras_generator.generate
        expected_path = 'spec/fixtures/pdf_fill/22-10216/overflow_redesign_extras.pdf'
        expect(FileUtils.compare_file(extras_path, expected_path)).to be(true)
        File.delete(extras_path)
      end
    end

    context 'when no field overflows' do
      let(:saved_claim) { create(:va10216) }

      it 'does not call combine_extras with overflow content' do
        expect(PdfFill::Filler).to receive(:combine_extras).once do |old_file_path, extras_generator|
          expect(extras_generator.text?).to be(false)
          old_file_path
        end

        saved_claim.to_pdf('abc')
      end
    end
  end
end
