# frozen_string_literal: true

require 'mhv/aal/activity'

module AAL
  ##
  # Model representing a paginated response of Account Activity Log entries.
  # Maps to the ActivityPage schema in the AAL OpenAPI specification.
  #
  class ActivityPage
    attr_reader :activities, :page_number, :page_size, :total_elements, :total_pages,
                :first_page, :last_page, :number_of_elements, :empty_page

    ##
    # Build an ActivityPage from the raw API response body.
    #
    # @param body [Hash] The parsed JSON response body from GET /usermgmt/external/activities
    # @return [AAL::ActivityPage]
    #
    def initialize(body)
      content = body['content'] || []
      @activities = content.map { |entry| AAL::Activity.from_api(entry) }

      pageable = body['pageable'] || {}
      @page_number = pageable['pageNumber'] || body['number'] || 0
      @page_size = pageable['pageSize'] || body['size'] || 0
      @total_elements = body['totalElements'] || 0
      @total_pages = body['totalPages'] || 0
      @first_page = body['first'] || false
      @last_page = body['last'] || false
      @number_of_elements = body['numberOfElements'] || 0
      @empty_page = body['empty'] || false
    end

    ##
    # Pagination metadata suitable for inclusion in a JSON response.
    #
    def pagination
      {
        page_number:,
        page_size:,
        total_elements:,
        total_pages:,
        first_page:,
        last_page:,
        number_of_elements:,
        empty_page:
      }
    end
  end
end
