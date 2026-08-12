# frozen_string_literal: true

require 'rails_helper'
require 'burials/pdf_stamper'

RSpec.describe Burials::PDFStamper do
  describe '.stamp_sets' do
    subject(:stamp_sets) { described_class.stamp_sets }

    let(:received_at_stamps) { stamp_sets[:burials_received_at] }
    let(:generated_claim_stamps) { stamp_sets[:burials_generated_claim] }

    shared_examples 'common stamp configuration' do
      it 'returns both :burials_received_at and :burials_generated_claim keys' do
        expect(stamp_sets).to include(:burials_received_at, :burials_generated_claim)
      end

      describe ':burials_received_at' do
        it 'contains a single VA.GOV stamp at the bottom-left' do
          expect(received_at_stamps.size).to eq(1)
          expect(received_at_stamps.first).to include(text: 'VA.GOV', x: 5, y: 5, timestamp: nil)
        end
      end

      describe ':burials_generated_claim' do
        it 'contains three stamps' do
          expect(generated_claim_stamps.size).to eq(3)
        end

        it 'includes a VA.GOV stamp at the bottom-left' do
          va_stamp = generated_claim_stamps.first
          expect(va_stamp).to include(text: 'VA.GOV', x: 5, y: 5, timestamp: nil)
        end

        it 'includes an FDC Reviewed stamp with text_only' do
          fdc_stamp = generated_claim_stamps.second
          expect(fdc_stamp).to include(
            text: 'FDC Reviewed - VA.gov Submission',
            x: 400,
            text_only: true,
            timestamp: nil
          )
        end

        it 'includes an Application Submitted stamp with multistamp on page 5' do
          app_stamp = generated_claim_stamps.third
          expect(app_stamp).to include(
            text: 'Application Submitted on va.gov',
            text_only: true,
            timestamp: nil,
            page_number: 5,
            multistamp: true,
            template: Burials.pdf_path
          )
        end
      end
    end

    context 'when V2 is enabled (burial_pdf_form_alignment flipper on)' do
      before do
        allow(Flipper).to receive(:enabled?).with(:burial_pdf_form_alignment).and_return(true)
      end

      include_examples 'common stamp configuration'

      it 'positions the FDC stamp at y=820' do
        fdc_stamp = generated_claim_stamps.second
        expect(fdc_stamp[:y]).to eq(820)
      end

      it 'positions the Application Submitted stamp at x=0 y=807' do
        app_stamp = generated_claim_stamps.third
        expect(app_stamp[:x]).to eq(472)
        expect(app_stamp[:y]).to eq(745)
      end

      it 'uses text size 8.5 for Application Submitted stamp' do
        app_stamp = generated_claim_stamps.third
        expect(app_stamp[:size]).to eq(8.5)
      end
    end

    context 'when V1 is active (burial_pdf_form_alignment flipper off)' do
      before do
        allow(Flipper).to receive(:enabled?).with(:burial_pdf_form_alignment).and_return(false)
      end

      include_examples 'common stamp configuration'

      it 'positions the FDC stamp at y=815' do
        fdc_stamp = generated_claim_stamps.second
        expect(fdc_stamp[:y]).to eq(815)
      end

      it 'positions the Application Submitted stamp at x=425 y=720' do
        app_stamp = generated_claim_stamps.third
        expect(app_stamp[:x]).to eq(425)
        expect(app_stamp[:y]).to eq(720)
      end

      it 'uses text size 9 for Application Submitted stamp' do
        app_stamp = generated_claim_stamps.third
        expect(app_stamp[:size]).to eq(9)
      end
    end
  end
end
