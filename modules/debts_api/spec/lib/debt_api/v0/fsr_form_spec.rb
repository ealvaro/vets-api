# frozen_string_literal: true

require 'rails_helper'
require 'debts_api/v0/fsr_form'

RSpec.describe DebtsApi::V0::FsrForm, type: :service do
  let(:fsr_form) { described_class.new }
  let(:form) { { 'additionalData' => { 'additionalComments' => 'Existing comment.' } } }

  before { allow(Flipper).to receive(:enabled?).with(:enable_hardship_suspension, anything).and_return(true) }

  describe '#get_resolution_option_text' do
    context 'when a debt has a compromise resolution option' do
      let(:debts) do
        [
          { 'resolutionOption' => 'compromise',
            'deductionCode' => '30',
            'resolutionComment' => '50' }
        ]
      end

      it 'formats the compromise amount with the deduction-code description' do
        result = fsr_form.get_resolution_option_text(debts)
        expect(result).to eq('Disability compensation and pension debt compromise amount: $50')
      end
    end

    context 'when a debt has a hardship-suspension resolution option' do
      let(:debts) do
        [
          { 'resolutionOption' => 'hardship-suspension',
            'deductionCode' => '30',
            'hardshipTimeframe' => '6-to-12-months' }
        ]
      end

      it 'formats the deduction code description, hardship description, and timeframe label' do
        result = fsr_form.get_resolution_option_text(debts)
        expect(result).to eq(
          'Disability compensation and pension debt - Hardship Suspension Request Information: ' \
          'I am experiencing temporary financial hardship and I estimate my financial situation ' \
          'to improve between 6-12 months'
        )
      end

      context 'when the hardship-suspension flag is off' do
        before do
          allow(Flipper).to receive(:enabled?).with(:enable_hardship_suspension, anything).and_return(false)
        end

        it 'contributes no text for hardship-suspension debts' do
          result = fsr_form.get_resolution_option_text(debts)
          expect(result).to eq('')
        end
      end
    end

    context 'when a debt has a waiver or monthly resolution option' do
      let(:debts) do
        [
          { 'resolutionOption' => 'waiver', 'deductionCode' => '30', 'resolutionComment' => '' },
          { 'resolutionOption' => 'monthly', 'deductionCode' => '41', 'resolutionComment' => '10' }
        ]
      end

      it 'contributes no text' do
        result = fsr_form.get_resolution_option_text(debts)
        expect(result).to eq('')
      end
    end

    context 'when there is a mix of compromise and hardship-suspension debts' do
      let(:debts) do
        [
          { 'resolutionOption' => 'compromise',
            'deductionCode' => '72',
            'resolutionComment' => '16' },
          { 'resolutionOption' => 'hardship-suspension',
            'deductionCode' => '30',
            'hardshipTimeframe' => 'within-6-months' }
        ]
      end

      it 'joins the formatted strings with commas in input order' do
        result = fsr_form.get_resolution_option_text(debts)
        expect(result).to eq(
          'Post-9/11 GI Bill debt for housing compromise amount: $16, ' \
          'Disability compensation and pension debt - Hardship Suspension Request Information: ' \
          'I am experiencing temporary financial hardship and I estimate my financial situation ' \
          'to improve within 6 months'
        )
      end

      context 'when the hardship-suspension flag is off' do
        before do
          allow(Flipper).to receive(:enabled?).with(:enable_hardship_suspension, anything).and_return(false)
        end

        it 'renders the compromise fragment and silently drops the hardship fragment' do
          result = fsr_form.get_resolution_option_text(debts)
          expect(result).to eq('Post-9/11 GI Bill debt for housing compromise amount: $16')
        end
      end
    end
  end

  describe '#add_additional_comments' do
    let(:debts) do
      [
        { 'resolutionOption' => 'compromise',
          'deductionCode' => '30',
          'resolutionComment' => '50' }
      ]
    end

    it 'appends the resolution option text to the existing additionalComments' do
      fsr_form.add_additional_comments(form, debts)
      expect(form['additionalData']['additionalComments']).to eq(
        'Existing comment. Disability compensation and pension debt compromise amount: $50'
      )
    end

    context 'when no debts produce resolution text' do
      let(:debts) { [{ 'resolutionOption' => 'waiver', 'resolutionComment' => '' }] }

      it 'leaves additionalComments unchanged' do
        fsr_form.add_additional_comments(form, debts)
        expect(form['additionalData']['additionalComments']).to eq('Existing comment.')
      end
    end

    context 'when existing additionalComments is blank' do
      let(:form) { { 'additionalData' => { 'additionalComments' => '' } } }

      it 'sets additionalComments to the resolution text without leading space' do
        fsr_form.add_additional_comments(form, debts)
        expect(form['additionalData']['additionalComments']).to eq(
          'Disability compensation and pension debt compromise amount: $50'
        )
      end
    end
  end

  describe '#aggregate_fsr_reasons' do
    it 'joins unique resolutionOption values with a comma' do
      personal_form = { 'personalIdentification' => {} }
      debts = [
        { 'resolutionOption' => 'waiver' },
        { 'resolutionOption' => 'compromise' },
        { 'resolutionOption' => 'waiver' }
      ]
      fsr_form.aggregate_fsr_reasons(personal_form, debts)
      expect(personal_form['personalIdentification']['fsrReason']).to eq('waiver, compromise')
    end

    it 'renders hardship-suspension as "hardship suspension" so the kebab does not appear on the PDF' do
      personal_form = { 'personalIdentification' => {} }
      debts = [{ 'resolutionOption' => 'hardship-suspension' }]
      fsr_form.aggregate_fsr_reasons(personal_form, debts)
      expect(personal_form['personalIdentification']['fsrReason']).to eq('hardship suspension')
    end

    it 'renders hardship-suspension alongside other options' do
      personal_form = { 'personalIdentification' => {} }
      debts = [
        { 'resolutionOption' => 'waiver' },
        { 'resolutionOption' => 'hardship-suspension' }
      ]
      fsr_form.aggregate_fsr_reasons(personal_form, debts)
      expect(personal_form['personalIdentification']['fsrReason']).to eq('waiver, hardship suspension')
    end

    it 'is a no-op when debts is blank' do
      personal_form = { 'personalIdentification' => { 'fsrReason' => 'untouched' } }
      fsr_form.aggregate_fsr_reasons(personal_form, [])
      expect(personal_form['personalIdentification']['fsrReason']).to eq('untouched')
    end
  end
end
