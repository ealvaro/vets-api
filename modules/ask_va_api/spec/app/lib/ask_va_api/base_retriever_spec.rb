# frozen_string_literal: true

require 'rails_helper'

module AskVAApi
  RSpec.describe BaseRetriever do
    subject(:retriever) { described_class.new(user_mock_data: false, entity_class: Class.new) }

    describe '#sort_by_rank_order_or_name' do
      def sort(items)
        retriever.send(:sort_by_rank_order_or_name, items).map { |item| item[:Name] }
      end

      it 'sorts rank 0 entries first, alphabetically by name' do
        items = [{ Name: 'Zulu', RankOrder: 0 }, { Name: 'Alpha', RankOrder: 0 }]
        expect(sort(items)).to eq(%w[Alpha Zulu])
      end

      it 'places rank 0 entries before non-zero entries, then sorts by RankOrder ascending' do
        items = [{ Name: 'Zulu', RankOrder: 0 }, { Name: 'Alpha', RankOrder: 0 },
                 { Name: 'Mid', RankOrder: 2 }, { Name: 'First', RankOrder: 1 }]
        expect(sort(items)).to eq(%w[Alpha Zulu First Mid])
      end

      it 'breaks ties at a non-zero RankOrder alphabetically by name' do
        items = [{ Name: 'Zebra', RankOrder: 2 }, { Name: 'Apple', RankOrder: 2 },
                 { Name: 'Mid', RankOrder: 1 }]
        expect(sort(items)).to eq(%w[Mid Apple Zebra])
      end

      it 'treats a nil RankOrder as 0' do
        items = [{ Name: 'Banana', RankOrder: 2 }, { Name: 'Apple', RankOrder: nil },
                 { Name: 'Cherry', RankOrder: 1 }]
        expect(sort(items)).to eq(%w[Apple Cherry Banana])
      end

      it 'returns an empty array when given no items' do
        expect(retriever.send(:sort_by_rank_order_or_name, [])).to eq([])
      end
    end
  end
end
