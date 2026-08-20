# frozen_string_literal: true

require 'rails_helper'
require 'pensions/pdf_fill/sections/section_01_v2'

describe Pensions::PdfFill::Section1V2 do
  describe '#expand' do
    it 'deletes vaFileNumber if veteran has not previously filed a claim' do
      form_data = { 'vaFileNumber' => '111223333', 'vaClaimHistory' => false }
      described_class.new.expand(form_data)
      expect(form_data).not_to have_key('vaFileNumber')
    end

    it 'retains vaFileNumber if veteran has previously filed a claim' do
      form_data = { 'vaFileNumber' => '111223333', 'vaClaimHistory' => true }
      expect(form_data).to have_key('vaFileNumber')
    end
  end
end
