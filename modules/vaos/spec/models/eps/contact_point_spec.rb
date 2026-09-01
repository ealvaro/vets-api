# frozen_string_literal: true

require 'rails_helper'

describe Eps::ContactPoint do
  describe '.phone_number' do
    context 'with the contact shape Wellhive documents' do
      let(:contact_details) do
        [
          { type: 'email', value: 'test@example.com' },
          { type: 'phone', value: '555-1234', use: 'work' },
          { type: 'phone', value: '555-5678', use: 'for-patient' }
        ]
      end

      it 'prefers the for-patient phone entry' do
        expect(described_class.phone_number(contact_details)).to eq('555-5678')
      end
    end

    it 'falls back to the first phone entry when none are for-patient' do
      contact_details = [
        { type: 'email', value: 'jones@example.com' },
        { type: 'phone', value: '555-9999', use: 'work' },
        { type: 'phone', value: '555-0000', use: 'home' }
      ]

      expect(described_class.phone_number(contact_details)).to eq('555-9999')
    end

    it 'ignores non-phone channels' do
      contact_details = [
        { type: 'email', value: 'nope@example.com' },
        { type: 'fax', value: '555-7777' }
      ]

      expect(described_class.phone_number(contact_details)).to be_nil
    end

    context 'when the payload diverges from the published schema' do
      it 'accepts a FHIR-style system key as the channel' do
        contact_details = [{ system: 'phone', value: '555-4321', use: 'for-patient' }]

        expect(described_class.phone_number(contact_details)).to eq('555-4321')
      end

      it 'accepts an underscored for_patient use value' do
        contact_details = [
          { type: 'phone', value: '555-1111', use: 'work' },
          { type: 'phone', value: '555-2222', use: 'for_patient' }
        ]

        expect(described_class.phone_number(contact_details)).to eq('555-2222')
      end

      it 'matches the channel case-insensitively' do
        contact_details = [{ type: 'Phone', value: '555-3333' }]

        expect(described_class.phone_number(contact_details)).to eq('555-3333')
      end
    end

    context 'with unusable input' do
      it 'returns nil for nil' do
        expect(described_class.phone_number(nil)).to be_nil
      end

      it 'returns nil for an empty array' do
        expect(described_class.phone_number([])).to be_nil
      end

      it 'returns nil when the phone entry has a blank value' do
        expect(described_class.phone_number([{ type: 'phone', value: '' }])).to be_nil
      end

      it 'skips nil entries rather than raising' do
        contact_details = [nil, { type: 'phone', value: '555-8888' }]

        expect(described_class.phone_number(contact_details)).to eq('555-8888')
      end

      it 'skips non-hash entries rather than raising' do
        contact_details = ['phone', %w[phone 555-0001], { type: 'phone', value: '555-8888' }]

        expect(described_class.phone_number(contact_details)).to eq('555-8888')
      end
    end
  end
end
