# frozen_string_literal: true

require 'rails_helper'
require 'search_kendra/response_adapter'

describe SearchKendra::ResponseAdapter do
  subject { described_class.new(response, query, page) }

  let(:response) do
    instance_double(
      Aws::Kendra::Types::QueryResult,
      total_number_of_results: total_results,
      result_items:,
      spell_corrected_queries:
    )
  end

  let(:query) { 'benefits' }
  let(:page) { 1 }
  let(:total_results) { 25 }
  let(:result_items) { [] }
  let(:spell_corrected_queries) { [] }

  describe '#body' do
    it 'returns expected response shape' do
      expect(subject.body).to eq(
        'query' => 'benefits',
        'web' => {
          'total' => 25,
          'next_offset' => 10,
          'spelling_correction' => nil,
          'results' => []
        },
        'text_best_bets' => [],
        'graphic_best_bets' => [],
        'health_topics' => [],
        'job_openings' => [],
        'recent_tweets' => [],
        'federal_register_documents' => [],
        'related_search_terms' => []
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
        expect(subject.body['web']['results']).to eq(
          [
            {
              'title' => 'VA Benefits',
              'url' => 'https://va.gov/benefits',
              'snippet' => 'Learn about benefits',
              'publication_date' => nil
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
          expect(subject.body['web']['results']).to eq(
            [
              {
                'title' => nil,
                'url' => 'https://va.gov/benefits',
                'snippet' => nil,
                'publication_date' => nil
              }
            ]
          )
        end
      end
    end

    context 'with a spelling correction' do
      let(:spell_corrected_queries) do
        [
          instance_double(
            Aws::Kendra::Types::SpellCorrectedQuery,
            suggested_query_text: 'corrected query'
          )
        ]
      end

      it 'returns the suggested query text' do
        expect(subject.body.dig('web', 'spelling_correction')).to eq('corrected query')
      end
    end
  end

  describe '#status' do
    it 'returns 200' do
      expect(subject.status).to eq(200)
    end
  end
end
