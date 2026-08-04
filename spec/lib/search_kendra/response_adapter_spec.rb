# frozen_string_literal: true

require 'rails_helper'
require 'search_kendra/response_adapter'

describe SearchKendra::ResponseAdapter do
  subject { described_class.new(response, page) }

  let(:response) do
    instance_double(
      Aws::Kendra::Types::QueryResult,
      total_number_of_results: total_results,
      result_items:
    )
  end

  let(:page) { 1 }
  let(:total_results) { 25 }
  let(:result_items) { [] }

  describe '#body' do
    it 'returns expected response shape' do
      expect(subject.body).to eq(
        'web' => {
          'total' => 25,
          'next_offset' => 10
        },
        'results' => []
      )
    end

    context 'when on the last page' do
      let(:page) { 2 }
      let(:total_results) { 15 }

      it 'returns nil for next offset' do
        expect(subject.body.dig('web', 'next_offset')).to be_nil
      end
    end

    context 'when results exactly fill the page' do
      let(:total_results) { 10 }

      it 'returns nil for next offset' do
        expect(subject.body.dig('web', 'next_offset')).to be_nil
      end
    end

    context 'with results' do
      let(:title) do
        instance_double(
          Aws::Kendra::Types::TextWithHighlights,
          text: 'VA Benefits'
        )
      end

      let(:excerpt) do
        instance_double(
          Aws::Kendra::Types::TextWithHighlights,
          text: 'Learn about benefits'
        )
      end

      let(:result_items) do
        [
          instance_double(
            Aws::Kendra::Types::QueryResultItem,
            document_title: title,
            document_uri: 'https://va.gov/benefits',
            document_excerpt: excerpt
          )
        ]
      end

      it 'maps Kendra result items' do
        expect(subject.body['results']).to eq(
          [
            {
              'title' => 'VA Benefits',
              'url' => 'https://va.gov/benefits',
              'snippet' => 'Learn about benefits'
            }
          ]
        )
      end

      context 'when a result has no title or excerpt' do
        let(:result_items) do
          [
            instance_double(
              Aws::Kendra::Types::QueryResultItem,
              document_title: nil,
              document_uri: 'https://va.gov/benefits',
              document_excerpt: nil
            )
          ]
        end

        it 'returns nil values' do
          expect(subject.body['results']).to eq(
            [
              {
                'title' => nil,
                'url' => 'https://va.gov/benefits',
                'snippet' => nil
              }
            ]
          )
        end
      end
    end
  end

  describe '#status' do
    it 'return 200' do
      expect(subject.status).to eq(200)
    end
  end
end
