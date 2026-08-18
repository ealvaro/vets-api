# frozen_string_literal: true

module SearchKendra
  class ResponseAdapter
    def initialize(response, query, page)
      @response = response
      @query = query
      @page = page.to_i
    end

    def status
      200
    end

    def body
      {
        'query' => query,
        'web' => {
          'total' => response.total_number_of_results,
          'next_offset' => next_offset,
          'spelling_correction' => spelling_correction,
          'results' => results
        },
        'text_best_bets' => [],
        'graphic_best_bets' => [],
        'health_topics' => [],
        'job_openings' => [],
        'recent_tweets' => [],
        'federal_register_documents' => [],
        'related_search_terms' => []
      }
    end

    private

    attr_reader :response, :page, :query

    def next_offset
      offset = page * Search::Pagination::ENTRIES_PER_PAGE
      offset if offset < response.total_number_of_results
    end

    def spelling_correction
      response.spell_corrected_queries&.first&.suggested_query_text
    end

    def results
      Array(response.result_items).map do |item|
        {
          'title' => item.document_title&.text,
          'url' => item.document_uri,
          'snippet' => item.document_excerpt&.text,
          'publication_date' => nil
        }
      end
    end
  end
end
