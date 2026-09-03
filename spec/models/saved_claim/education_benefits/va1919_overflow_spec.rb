# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/filler'

# Tests the ExtrasGeneratorV2 overflow page wired up via VA1919#to_pdf's extras_redesign
# fill_options (see lib/pdf_fill/forms/va221919.rb's QUESTION_KEY/START_PAGE).
describe SavedClaim::EducationBenefits::VA1919 do
  before do
    allow(Flipper).to receive(:enabled?).with(:saved_claim_pdf_overflow_tracking).and_return(false)
  end

  after do
    FileUtils.rm_rf('tmp/pdfs')
  end

  describe '#to_pdf' do
    context 'when the institution name/address, employee/official names, and signature overflow' do
      let(:saved_claim) { create(:va1919_overflow) }

      it 'renders the overflow page using ExtrasGeneratorV2' do
        the_extras_generator = nil
        expect(PdfFill::Filler).to receive(:combine_extras).once do |old_file_path, extras_generator|
          the_extras_generator = extras_generator
          old_file_path
        end

        saved_claim.to_pdf('abc')

        extras_path = the_extras_generator.generate
        expected_path = 'spec/fixtures/pdf_fill/22-1919/overflow_redesign_extras.pdf'
        expect(FileUtils.compare_file(extras_path, expected_path)).to be(true)
        File.delete(extras_path)
      end
    end
  end
end
