# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TooltipSerializer do
  let(:user_account) { create(:user_account) }
  let(:tooltip) do
    create(:tooltip,
           user_account:,
           tooltip_name: 'test_tooltip',
           hidden: false,
           counter: 2,
           metadata: { test_key: 'test_value' })
  end

  describe '#serializable_hash' do
    context 'with a single tooltip' do
      subject(:serialized) { described_class.new(tooltip).serializable_hash }

      it 'includes allowed attributes' do
        expect(serialized).to include(
          id: tooltip.id,
          tooltip_name: 'test_tooltip',
          hidden: false,
          counter: 2,
          metadata: { 'test_key' => 'test_value' }
        )
      end

      it 'includes timestamp attributes' do
        expect(serialized).to include(:last_signed_in, :created_at, :updated_at)
      end

      it 'does NOT include user_account_id' do
        expect(serialized).not_to have_key(:user_account_id)
      end
    end

    context 'with a collection of tooltips' do
      subject(:serialized) { described_class.new([tooltip, tooltip2]).serializable_hash }

      let(:tooltip2) { create(:tooltip, user_account:, tooltip_name: 'another_tooltip') }

      it 'returns an array' do
        expect(serialized).to be_an(Array)
        expect(serialized.length).to eq(2)
      end

      it 'serializes each tooltip without user_account_id' do
        serialized.each do |item|
          expect(item).not_to have_key(:user_account_id)
          expect(item).to include(:id, :tooltip_name, :hidden, :counter)
        end
      end
    end

    context 'with an empty collection' do
      subject(:serialized) { described_class.new([]).serializable_hash }

      it 'returns an empty array' do
        expect(serialized).to eq([])
      end
    end
  end

  describe '#as_json' do
    it 'is aliased to serializable_hash' do
      serializer = described_class.new(tooltip)
      expect(serializer.as_json).to eq(serializer.serializable_hash)
    end
  end
end
