# frozen_string_literal: true

require 'rails_helper'
require 'meb_api/confirmation_email_config'

RSpec.describe MebApi::ConfirmationEmailConfig do
  describe '.normalize_claim_status' do
    it 'returns the status for known DGI backend values' do
      %w[ELIGIBLE DENIED INPROGRESS ERROR].each do |status|
        expect(described_class.normalize_claim_status(status)).to eq(status)
      end
    end

    it 'maps frontend IN_PROGRESS to backend INPROGRESS' do
      expect(described_class.normalize_claim_status('IN_PROGRESS')).to eq('INPROGRESS')
    end

    it 'normalizes to uppercase' do
      expect(described_class.normalize_claim_status('eligible')).to eq('ELIGIBLE')
    end

    it 'returns OTHER for unknown statuses' do
      expect(described_class.normalize_claim_status('UNKNOWN')).to eq('OTHER')
      expect(described_class.normalize_claim_status('PENDING')).to eq('OTHER')
      expect(described_class.normalize_claim_status('OFFRAMP')).to eq('OTHER')
    end
  end

  describe '.template_id' do
    let(:template_settings) do
      double(
        'template_id',
        form1990meb_approved_confirmation_email: 'meb_approved',
        form1990meb_denied_confirmation_email: 'meb_denied',
        form1990meb_offramp_confirmation_email: 'meb_offramp',
        form1990emeb_approved_confirmation_email: 'emeb_approved',
        form1990emeb_denied_confirmation_email: 'emeb_denied',
        form1990emeb_offramp_confirmation_email: 'emeb_offramp',
        form10297_approved_confirmation_email: '10297_approved',
        form10297_denied_confirmation_email: '10297_denied',
        form10297_under_review_confirmation_email: '10297_under_review',
        form225490_approved_confirmation_email: '225490_approved',
        form225490_offramp_confirmation_email: '225490_offramp',
        form1990_chapter1606_approved_confirmation_email: '1990_chapter1606_approved',
        form1990_chapter1606_offramp_confirmation_email: '1990_chapter1606_offramp',
        form1990_chapter30_approved_confirmation_email: '1990_chapter30_approved',
        form1990_chapter30_offramp_confirmation_email: '1990_chapter30_offramp'
      )
    end

    before do
      allow(Settings.vanotify.services.va_gov).to receive(:template_id).and_return(template_settings)
    end

    context 'with FORM_1990MEB' do
      it 'returns the approved template for ELIGIBLE' do
        result = described_class.template_id(form_type: '1990MEB', claim_status: 'ELIGIBLE')
        expect(result).to eq('meb_approved')
      end

      it 'returns the denied template for DENIED' do
        result = described_class.template_id(form_type: '1990MEB', claim_status: 'DENIED')
        expect(result).to eq('meb_denied')
      end

      it 'returns the offramp template for other statuses' do
        result = described_class.template_id(form_type: '1990MEB', claim_status: 'PENDING')
        expect(result).to eq('meb_offramp')
      end
    end

    context 'with FORM_1990EMEB' do
      it 'returns the approved template for ELIGIBLE' do
        result = described_class.template_id(form_type: '1990EMEB', claim_status: 'ELIGIBLE')
        expect(result).to eq('emeb_approved')
      end

      it 'returns the denied template for DENIED' do
        result = described_class.template_id(form_type: '1990EMEB', claim_status: 'DENIED')
        expect(result).to eq('emeb_denied')
      end

      it 'returns the offramp template for other statuses' do
        result = described_class.template_id(form_type: '1990EMEB', claim_status: 'INPROGRESS')
        expect(result).to eq('emeb_offramp')
      end
    end

    context 'with FORM_10297' do
      it 'returns the approved template for ELIGIBLE' do
        result = described_class.template_id(form_type: '10297', claim_status: 'ELIGIBLE')
        expect(result).to eq('10297_approved')
      end

      it 'returns the denied template for DENIED' do
        result = described_class.template_id(form_type: '10297', claim_status: 'DENIED')
        expect(result).to eq('10297_denied')
      end

      it 'returns the under_review template for INPROGRESS' do
        result = described_class.template_id(form_type: '10297', claim_status: 'INPROGRESS')
        expect(result).to eq('10297_under_review')
      end

      it 'returns the under_review template for PENDING' do
        result = described_class.template_id(form_type: '10297', claim_status: 'PENDING')
        expect(result).to eq('10297_under_review')
      end
    end

    context 'with FORM_225490' do
      it 'returns the approved template for ELIGIBLE' do
        result = described_class.template_id(form_type: '225490', claim_status: 'ELIGIBLE')
        expect(result).to eq('225490_approved')
      end

      it 'returns the offramp template for INPROGRESS' do
        result = described_class.template_id(form_type: '225490', claim_status: 'INPROGRESS')
        expect(result).to eq('225490_offramp')
      end

      it 'returns the offramp template for DENIED' do
        result = described_class.template_id(form_type: '225490', claim_status: 'DENIED')
        expect(result).to eq('225490_offramp')
      end

      it 'returns the offramp template for ERROR' do
        result = described_class.template_id(form_type: '225490', claim_status: 'ERROR')
        expect(result).to eq('225490_offramp')
      end
    end

    context 'with FORM_1990_CHAPTER1606' do
      it 'returns the approved template for ELIGIBLE' do
        result = described_class.template_id(form_type: '1990_CHAPTER1606', claim_status: 'ELIGIBLE')
        expect(result).to eq('1990_chapter1606_approved')
      end

      it 'returns the offramp template for DENIED' do
        result = described_class.template_id(form_type: '1990_CHAPTER1606', claim_status: 'DENIED')
        expect(result).to eq('1990_chapter1606_offramp')
      end

      it 'returns the offramp template for other statuses' do
        result = described_class.template_id(form_type: '1990_CHAPTER1606', claim_status: 'PENDING')
        expect(result).to eq('1990_chapter1606_offramp')
      end
    end

    context 'with FORM_1990_CHAPTER30' do
      it 'returns the approved template for ELIGIBLE' do
        result = described_class.template_id(form_type: '1990_CHAPTER30', claim_status: 'ELIGIBLE')
        expect(result).to eq('1990_chapter30_approved')
      end

      it 'returns the offramp template for DENIED' do
        result = described_class.template_id(form_type: '1990_CHAPTER30', claim_status: 'DENIED')
        expect(result).to eq('1990_chapter30_offramp')
      end

      it 'returns the offramp template for other statuses' do
        result = described_class.template_id(form_type: '1990_CHAPTER30', claim_status: 'INPROGRESS')
        expect(result).to eq('1990_chapter30_offramp')
      end
    end
  end
end
