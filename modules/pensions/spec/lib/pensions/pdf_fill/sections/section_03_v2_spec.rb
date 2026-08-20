# frozen_string_literal: true

require 'rails_helper'
require 'pensions/pdf_fill/sections/section_03_v2'

describe Pensions::PdfFill::Section3V2 do
  describe '#expand' do
    subject(:expand) { described_class.new.expand(form_data) }

    let(:form_data) do
      {
        'serviceBranch' => { 'army' => true, 'navy' => false },
        'placeOfSeparation' => 'White Sulpher Springs, MT'
      }
    end

    before { allow(Pensions).to receive(:use_v2?).and_return(true) }

    it 'formats service branch checkboxes' do
      expect { expand }.to change { form_data['serviceBranch'] }
        .from({ 'army' => true, 'navy' => false })
        .to({ 'army' => 'Yes', 'navy' => 'Off' })
    end

    it 'divides place of separation into two lines if below character limit' do
      expect(form_data['placeOfSeparation'].length).to be < described_class::SEPARATION_LIMIT
      expand
      expect(form_data['placeOfSeparationLineOne']).to eq('White Sulpher Spri')
      expect(form_data['placeOfSeparationLineTwo']).to eq('ngs, MT')
    end

    it 'repurposes place of separation line one for overflow when over character limit' do
      placename = 'La Villa Real de la Santa Fe de San Francisco de Asís, NM'
      form_data['placeOfSeparation'] = placename
      expand
      expect(form_data).not_to have_key('placeOfSeparation')
      expect(form_data['placeOfSeparationLineOne']).to eq(placename)
      expect(form_data['placeOfSeparationLineTwo']).to be_nil
    end

    it 'sets POW radio off if POW date range not present' do
      expand
      expect(form_data['pow']).to eq(1)
    end

    it 'sets POW radio on if POW date range present' do
      form_data['powDateRange'] = { 'from' => '1971-02-26', 'to' => '1973-03-02' }
      expand
      expect(form_data['pow']).to eq(0)
    end
  end
end
