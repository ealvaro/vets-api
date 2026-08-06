# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampvaSponsor, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:transaction_uuid) }
  end

  describe 'factory' do
    it 'is valid with only transaction_uuid' do
      sponsor = described_class.new(transaction_uuid: SecureRandom.uuid)
      expect(sponsor).to be_valid
    end

    it 'is invalid without transaction_uuid' do
      sponsor = described_class.new(first_name: 'John', last_name: 'Smith')
      expect(sponsor).not_to be_valid
    end
  end

  describe 'encryption' do
    it 'encrypts first_name' do
      expect(described_class.new).to encrypt_attr(:first_name)
    end

    it 'encrypts last_name' do
      expect(described_class.new).to encrypt_attr(:last_name)
    end

    it 'encrypts sponsor_icn' do
      expect(described_class.new).to encrypt_attr(:sponsor_icn)
    end
  end
end
