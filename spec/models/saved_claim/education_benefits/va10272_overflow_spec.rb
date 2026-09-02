# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/filler'

# Tests the ExtrasGeneratorV2 overflow page wired up via VA10272#to_pdf's extras_redesign
# fill_options (see lib/pdf_fill/forms/va2210272.rb's QUESTION_KEY/SECTIONS/START_PAGE).
describe SavedClaim::EducationBenefits::VA10272 do
  before do
    allow(Flipper).to receive(:enabled?).with(:saved_claim_pdf_overflow_tracking).and_return(false)
  end

  after do
    FileUtils.rm_rf('tmp/pdfs')
  end

  describe '#to_pdf' do
    context 'when the mailing address, organization address, prep course name, and remarks overflow' do
      let(:saved_claim) { create(:va10272_overflow) }

      it 'renders the overflow page using ExtrasGeneratorV2' do
        the_extras_generator = nil
        expect(PdfFill::Filler).to receive(:combine_extras).once do |old_file_path, extras_generator|
          the_extras_generator = extras_generator
          old_file_path
        end

        saved_claim.to_pdf('abc')

        extras_path = the_extras_generator.generate
        expected_path = 'spec/fixtures/pdf_fill/22-10272/overflow_redesign_extras.pdf'
        expect(FileUtils.compare_file(extras_path, expected_path)).to be(true)
        File.delete(extras_path)
      end
    end
  end
end
