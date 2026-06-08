# frozen_string_literal: true

require 'rails_helper'

describe IncreaseCompensation::PdfFill::Section1 do
  describe 'Phone Number overflows' do
    it 'Handles NANP phone numbers' do
      s2 = described_class.new
      data = { 'veteranPhone' => '12025551234' }
      s2.expand(data)
      expect(data['veteranPhone']).to eq(
        {
          'phone_area_code' => '202',
          'phone_first_three_numbers' => '555',
          'phone_last_four_numbers' => '1234'
        }
      )
      data['veteranPhone'] = '2025551234'
      s2.expand(data)
      expect(data['veteranPhone']).to eq(
        {
          'phone_area_code' => '202',
          'phone_first_three_numbers' => '555',
          'phone_last_four_numbers' => '1234'
        }
      )
    end

    it 'handles international numbers by forcing overflow' do
      s2 = described_class.new
      data = { 'veteranPhone' => '442025551234' }
      s2.expand(data)
      expect(data['veteranPhone']).to eq(
        {
          'phone_area_code' => '442025551234',
          'phone_first_three_numbers' => 'add',
          'phone_last_four_numbers' => 'page'
        }
      )
    end

    it 'handles falsey values' do
      s2 = described_class.new
      data = { 'veteranPhone' => '' }
      s2.expand(data)
      expect(data['veteranPhone']).to eq('')
      data['veteranPhone'] = nil
      s2.expand(data)
      expect(data['veteranPhone']).to eq('')
    end
  end
end
