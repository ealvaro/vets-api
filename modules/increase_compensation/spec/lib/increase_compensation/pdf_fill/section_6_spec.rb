# frozen_string_literal: true

require 'rails_helper'

describe IncreaseCompensation::PdfFill::Section6 do
  include PdfFill::Forms::FormHelper
  # prevents name fallback behavior from erroring
  name = {
    'first' => 'Johnny',
    'middleinitial' => 'Juan',
    'last' => 'Rico'
  }
  describe 'date fallback' do
    it 'fallsback to a generated date in none is sent with submission' do
      fallback_date = Date.current.in_time_zone('America/Chicago').strftime('%Y-%m-%d')
      s6 = described_class.new
      # Provided behavior
      data = {
        'veteranFullName' => name,
        'signatureDate' => '2025-10-29'
      }
      s6.expand(data)
      expect(data['signatureDate']).to eq({ 'year' => '2025', 'month' => '10', 'day' => '29' })

      # Fallback behavior
      data = { 'signatureDate' => '', 'veteranFullName' => name }
      s6.expand(data)
      expect(data['signatureDate']).to eq(split_date(fallback_date))
    end
  end

  describe '#handle_witnesses' do
    let(:s6) { described_class.new }

    it 'Overflows a long address' do
      data = {
        'veteranFullName' => name,
        'witnessSignature2' => {
          'signature' => 'Carl Jenkins',
          'address' => '456 Medical street, Cheyenne, WY 82001'
        }
      }
      s6.expand(data)
      expect(data['witnessSignature2']['address1']).to eq('456 Medical street, Cheyenne, WY 82001')
    end

    it 'return empty object if nil' do
      data = { 'veteranFullName' => name }
      s6.expand(data)
      expect(data['witnessSignature1']).to eq({})
      expect(data['witnessSignature2']).to eq({})
    end

    it 'split long addresses accross 2 lines' do
      data = {
        'veteranFullName' => name,
        'witnessSignature1' => {
          'signature' => 'Carmen Ibanez',
          'address' => '303 Fleet ave, Cheyenne, WY 82001'
        },
        'witnessSignature2' => {
          'signature' => 'Carl Jenkins',
          'address' => '456 Medical st'
        }
      }
      s6.expand(data)
      expect(data['witnessSignature1']['address1']).to eq('303 Fleet ave, Ch')
      expect(data['witnessSignature1']['address2']).to eq('eyenne, WY 82001')
      expect(data['witnessSignature2']['address1']).to eq('456 Medical st')
      expect(data['witnessSignature2']['address2']).to be_nil
    end
  end
end
