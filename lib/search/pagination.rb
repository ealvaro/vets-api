# frozen_string_literal: true

module Search
  # A Utility class encapsulating logic to calculate pagination offsets from a given results set.
  #
  # @attr_reader [Integer] total
  # @param (see Pagination#initialize)
  #
  class Pagination
    # Default size for per-request results count is 20 per page, max is 50.
    # Our design choice is to display 10 results per page.
    #
    # @see https://search.usa.gov/sites/6277/api_instructions
    #
    ENTRIES_PER_PAGE = 10

    # Due to Search.gov's offset max of 999, we cannot view pages
    # where the offset param exceeds 999.  This influences our:
    #   - total_viewable_pages
    #   - total_viewable_entries
    #
    # @see https://search.usa.gov/sites/7378/api_instructions under `offset`
    #
    OFFSET_LIMIT = 999

    attr_reader :next_offset, :total_entries, :total_pages

    # @param [Hash] raw_body a Hash from the 'web' object found in the results response
    #
    def initialize(raw_body)
      body = raw_body.is_a?(Hash) ? raw_body : {}
      @next_offset = body.dig('web', 'next_offset') # intentionally nil-able; current_page handles nil
      @total_entries = body.dig('web', 'total').to_i # .to_i guards against nil arithmetic (nil / float raises)
      @total_pages = (total_entries / ENTRIES_PER_PAGE.to_f).ceil
    end

    # @return [Hash] pagination_object a Hash including pagination details
    #
    def object
      pagination_object
    end

    # Calculates the Search.gov `offset` query param for a requested page number.
    # This is the true determinant of which upstream result window is fetched:
    # any page <= 1 maps to offset 0 (first page), and the offset is capped at
    # OFFSET_LIMIT. Shared by the request services and the results cache key so
    # they stay aligned.
    #
    # @param page [Integer, String, nil] the requested page number
    # @return [Integer]
    def self.offset_for(page)
      page = page.to_i
      return 0 if page <= 1

      [(page - 1) * ENTRIES_PER_PAGE, OFFSET_LIMIT].min
    end

    private

    def current_page
      case next_offset
      when nil
        total_pages.to_i
      else
        (next_offset / ENTRIES_PER_PAGE.to_f).floor
      end
    end

    def pagination_object
      {
        'current_page' => [current_page, total_viewable_pages].min,
        'per_page' => ENTRIES_PER_PAGE,
        'total_pages' => total_viewable_pages,
        'total_entries' => total_viewable_entries
      }
    end

    def total_viewable_pages
      [total_pages, maximum_viewable_pages].min
    end

    def maximum_viewable_pages
      (OFFSET_LIMIT / ENTRIES_PER_PAGE.to_f).floor
    end

    def total_viewable_entries
      [total_entries, maximum_viewable_entries].min
    end

    def maximum_viewable_entries
      (ENTRIES_PER_PAGE * total_viewable_pages) + (ENTRIES_PER_PAGE - 1)
    end
  end
end
