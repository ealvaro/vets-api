# frozen_string_literal: true

module RepresentationManagement
  class OriginalEntityQuery
    MAXIMUM_RESULT_COUNT = 10
    WORD_SIMILARITY_THRESHOLD = 0.7

    # Initializes a new instance of OriginalEntityQuery.
    #
    # @param query_string [String] the string to be used for querying veteran_x entities.
    def initialize(query_string)
      @query_string = query_string
    end

    # Executes the query and returns the results as an array of objects.
    #
    # @return [Array<Veteran::Service::Representative, Veteran::Service::Organization>] an array of veteran_x entities
    #   that match the query string, sorted by their similarity distance. The array will be empty
    #   if the query string is blank.
    def results
      return [] if @query_string.blank?

      representatives, organizations = select_and_sort_original_entities
      organized_results(representatives, organizations)
    end

    private

    # rubocop:disable Metrics/MethodLength
    def select_and_sort_original_entities
      representatives = Veteran::Service::Representative
                        .select('*',
                                'representative_id AS id',
                                'full_name AS name',
                                'full_name AS full_name',
                                Arel.sql('word_similarity(?, full_name) AS similarity',
                                         @query_string))
                        .where.not(location: nil)
                        .where(['word_similarity(?, full_name) >= ? ', @query_string,
                                WORD_SIMILARITY_THRESHOLD])
                        .order('similarity DESC')
                        .limit(MAXIMUM_RESULT_COUNT)

      organizations = Veteran::Service::Organization
                      .select('*',
                              'poa AS id',
                              'name',
                              Arel.sql('word_similarity(?, name) AS similarity',
                                       @query_string))
                      .where.not(location: nil)
                      .where(['word_similarity(?, name) >= ? ', @query_string,
                              WORD_SIMILARITY_THRESHOLD])
                      .order('similarity DESC')
                      .limit(MAXIMUM_RESULT_COUNT)

      [representatives, organizations]
    end
    # rubocop:enable Metrics/MethodLength

    def organized_results(representatives, organizations)
      (representatives + organizations).sort_by { |result| result['similarity'] }.last(MAXIMUM_RESULT_COUNT).reverse
    end
  end
end
