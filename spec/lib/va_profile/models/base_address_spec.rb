# frozen_string_literal: true

require 'rails_helper'
require 'va_profile/models/base_address'

describe VAProfile::Models::BaseAddress, type: :model do
  let(:domestic_address) { build(:va_profile_address, :domestic) }
  let(:international_address) do
    build(
      :va_profile_address,
      :international,
      address_line1: 'Cumhuriyet Caddesi',
      address_line2: 'Çiçek Sok.',
      address_line3: 'Gü1 Ap. No:25/4',
      city: 'Bayrampaşa',
      province: 'İstanbul',
      country_name: 'Türkiye',
      international_postal_code: '34040'
    )
  end

  describe '#strip_whitespace' do
    it 'strips leading and trailing whitespace' do
      domestic_address.address_line1 = '  123 Main St  '
      domestic_address.valid?
      expect(domestic_address.address_line1).to eq('123 Main St')
    end

    it 'handles nil values without error' do
      domestic_address.address_line2 = nil
      domestic_address.address_line3 = nil
      expect { domestic_address.valid? }.not_to raise_error
    end
  end

  describe '#validate_address_characters' do
    context 'when flipper is disabled (ASCII-only mode)' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:profile_international_address_validation_enabled)
          .and_return(false)
      end

      it 'is valid with ASCII characters' do
        expect(domestic_address).to be_valid
      end

      it 'is invalid with non-ASCII characters' do
        domestic_address.address_line1 = 'Café Street'
        expect(domestic_address).not_to be_valid
        expect(domestic_address.errors[:address]).to include('must contain ASCII characters only')
      end
    end

    context 'when flipper is enabled (UTF-8 mode)' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:profile_international_address_validation_enabled)
          .and_return(true)
      end

      it 'is valid with a full domestic ASCII address' do
        expect(domestic_address).to be_valid
      end

      it 'is valid with tabs (U+0009)' do
        domestic_address.address_line1 = "123\tMain St"
        expect(domestic_address).to be_valid
      end

      it 'is invalid with control characters' do
        domestic_address.address_line1 = "123\x00Main St"
        expect(domestic_address).not_to be_valid
        expect(domestic_address.errors[:address]).to include('contains invalid characters')
      end

      it 'is valid with a full international address containing unicode characters' do
        expect(international_address).to be_valid
      end
    end
  end
end
