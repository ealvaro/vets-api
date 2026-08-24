# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/filler'

# Tests the ExtrasGeneratorV2 overflow page wired up via VA0803#to_pdf's extras_redesign
# fill_options (see lib/pdf_fill/forms/va220803.rb's QUESTION_KEY/SECTIONS/START_PAGE).
describe SavedClaim::EducationBenefits::VA0803 do
  before do
    allow(Flipper).to receive(:enabled?).with(:saved_claim_pdf_overflow_tracking).and_return(false)
  end

  after do
    FileUtils.rm_rf('tmp/pdfs')
  end

  describe '#to_pdf' do
    context 'when the remarks field overflows' do
      let(:saved_claim) { create(:va0803_overflow) }

      it 'renders the overflow page using ExtrasGeneratorV2' do
        the_extras_generator = nil
        expect(PdfFill::Filler).to receive(:combine_extras).once do |old_file_path, extras_generator|
          the_extras_generator = extras_generator
          old_file_path
        end

        saved_claim.to_pdf('abc')

        extras_path = the_extras_generator.generate
        expected_path = Rails.root.join('spec', 'fixtures', 'pdf_fill', '22-0803', 'overflow_extras.pdf')
        expect(extras_path).to match_file_exactly(expected_path)
        File.delete(extras_path)
      end
    end

    context 'when the remarks field does not overflow' do
      let(:saved_claim) { create(:va0803) }

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
