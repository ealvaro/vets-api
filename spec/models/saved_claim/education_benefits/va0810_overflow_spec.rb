# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/filler'

# Tests the ExtrasGeneratorV2 overflow page wired up via VA0810#to_pdf's extras_redesign
# fill_options (see lib/pdf_fill/forms/va220810.rb's QUESTION_KEY/SECTIONS/START_PAGE).
describe SavedClaim::EducationBenefits::VA0810 do
  before do
    allow(Flipper).to receive(:enabled?).with(:saved_claim_pdf_overflow_tracking).and_return(false)
  end

  after do
    FileUtils.rm_rf('tmp/pdfs')
  end

  describe '#to_pdf' do
    context 'when the mailing address and organization address overflow' do
      let(:saved_claim) { create(:va0810_overflow) }

      it 'renders the overflow page using ExtrasGeneratorV2' do
        the_extras_generator = nil
        expect(PdfFill::Filler).to receive(:combine_extras).once do |old_file_path, extras_generator|
          the_extras_generator = extras_generator
          old_file_path
        end

        saved_claim.to_pdf('abc')

        extras_path = the_extras_generator.generate
        expected_path = 'spec/fixtures/pdf_fill/22-0810/overflow_redesign_extras.pdf'
        expect(FileUtils.compare_file(extras_path, expected_path)).to be(true)
        File.delete(extras_path)
      end
    end

    context 'when both the mailing and organization address overflow' do
      # minimal.json's mailing address includes a street2/apartment line, so both the
      # mailing address (question 2, multiline_limit of 2) and the organization address
      # (question 8, which always overflows due to its multiline_limit of 1) end up on
      # the overflow page.
      let(:saved_claim) { create(:va0810) }

      it 'renders both addresses on the overflow page' do
        the_extras_generator = nil
        expect(PdfFill::Filler).to receive(:combine_extras).once do |old_file_path, extras_generator|
          the_extras_generator = extras_generator
          old_file_path
        end

        saved_claim.to_pdf('abc')

        expect(the_extras_generator.text?).to be(true)
        questions = the_extras_generator.instance_variable_get(:@questions).compact
        expect(questions.select { |_, q| q.overflow }.keys).to eq(%w[2 8])
      end
    end
  end
end
