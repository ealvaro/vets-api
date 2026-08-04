# frozen_string_literal: true

module SearchKendra
  class ResponseAdapter
    def initialize(response, page)
      @response = response
      @page = page.to_i
    end

    def status
      200
    end

    def body
      {
        'web' => {
          'total' => response.total_number_of_results,
          'next_offset' => next_offset
        },
        'results' => results
      }
    end

    private

    attr_reader :response, :page

    def next_offset
      offset = page * Search::Pagination::ENTRIES_PER_PAGE
      offset if offset < response.total_number_of_results
    end

    def results
      Array(response.result_items).map do |item|
        {
          'title' => item.document_title&.text,
          'url' => item.document_uri,
          'snippet' => item.document_excerpt&.text
        }
      end
    end
  end
end
