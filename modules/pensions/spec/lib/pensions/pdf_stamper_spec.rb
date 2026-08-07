# frozen_string_literal: true

require 'rails_helper'
require 'pensions/pdf_stamper'

RSpec.describe Pensions::PDFStamper do
  describe '.stamp_sets' do
    let(:stamp_sets) do
      {
        pensions_received_at: [{
          text: 'VA.GOV',
          timestamp: nil,
          x: 5,
          y: 5
        }],
        pensions_generated_claim: [{
          text: 'VA.GOV',
          timestamp: nil,
          x: 5,
          y: 5
        }, {
          text: 'FDC Reviewed - VA.gov Submission',
          timestamp: nil,
          x: 430,
          y: fdc_y,
          text_only: true
        }, {
          text: 'Application Submitted on va.gov',
          x: 440,
          y: 745,
          text_only: true,
          timestamp: nil,
          page_number:,
          size: 9,
          template: pdf_path,
          multistamp: true
        }]
      }
    end

    context 'when pension_pdf_form_alignment flipper is disabled' do
      let(:pdf_path) { Pensions::V1_PDF_PATH }
      let(:fdc_y) { 820 }
      let(:page_number) { 0 }

      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false) }

      it 'returns stamp set with version 1 PDF path' do
        expect(described_class.stamp_sets).to eq(stamp_sets)
      end
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      let(:pdf_path) { Pensions::V2_PDF_PATH }
      let(:fdc_y) { 825 }
      let(:page_number) { 7 }

      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true) }

      it 'returns stamp set with version 2 PDF Path' do
        expect(described_class.stamp_sets).to eq(stamp_sets)
      end
    end
  end
end
