# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pensions do
  describe '.use_v2?' do
    context 'when pension_pdf_form_alignment flipper is disabled' do
      it 'returns false' do
        allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false)

        expect(described_class.use_v2?).to be false
      end
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      it 'returns true' do
        allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true)

        expect(described_class.use_v2?).to be true
      end
    end

    context 'when Flipper raises an error' do
      it 'defaults to false' do
        allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_raise(ActiveRecord::NoDatabaseError)

        expect(described_class.use_v2?).to be false
      end
    end
  end

  describe '.pdf_path' do
    context 'when pension_pdf_form_alignment flipper is disabled' do
      it 'returns the V1 PDF path' do
        allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false)

        expect(described_class.pdf_path).to eq(Pensions::V1_PDF_PATH)
      end
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      it 'returns the V2 PDF path' do
        allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true)

        expect(described_class.pdf_path).to eq(Pensions::V2_PDF_PATH)
      end

      context 'when Flipper raises an error' do
        it 'defaults to V1 PDF Path' do
          allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_raise(ActiveRecord::NoDatabaseError)

          expect(described_class.pdf_path).to eq(Pensions::V1_PDF_PATH)
        end
      end
    end
  end
end
