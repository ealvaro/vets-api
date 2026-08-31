# frozen_string_literal: true

module RepresentationManagement
  class AccreditedEntityQuery
    MAXIMUM_RESULT_COUNT = 10
    WORD_SIMILARITY_THRESHOLD = 0.7

    # Initializes a new instance of AccreditedEntityQuery.
    #
    # @param query_string [String] the string to be used for querying accredited entities.
    def initialize(query_string)
      @query_string = query_string
    end

    # Executes the query and returns the results as an array of objects.
    #
    # @return [Array<AccreditedIndividual, AccreditedOrganization>]
    #   an array of accredited entities that match the query string, sorted by their similarity
    #   distance. The array will be empty if the query string is blank.
    def results
      return [] if @query_string.blank?

      individuals, organizations = select_and_sort_accredited_entities
      organized_results(individuals, organizations)
    end

    private

    # rubocop:disable Metrics/MethodLength
    def select_and_sort_accredited_entities
      individuals = AccreditedIndividual
                    .select('*',
                            'id',
                            'full_name AS name',
                            Arel.sql(
                              ActiveRecord::Base.sanitize_sql_array(
                                ['word_similarity(?, full_name) AS similarity', @query_string]
                              )
                            ))
                    .eligible_for_search
                    .where(['word_similarity(?, full_name) >= ? ', @query_string,
                            WORD_SIMILARITY_THRESHOLD])
                    .order('similarity DESC')
                    .limit(MAXIMUM_RESULT_COUNT)

      organizations = AccreditedOrganization
                      .select('*',
                              'id',
                              'name',
                              Arel.sql(
                                ActiveRecord::Base.sanitize_sql_array(
                                  ['word_similarity(?, name) AS similarity', @query_string]
                                )
                              ))
                      .where.not(location: nil)
                      .where(['word_similarity(?, name) >= ? ', @query_string,
                              WORD_SIMILARITY_THRESHOLD])
                      .order('similarity DESC')
                      .limit(MAXIMUM_RESULT_COUNT)

      [individuals, organizations]
    end
    # rubocop:enable Metrics/MethodLength

    def organized_results(individuals, organizations)
      (individuals + organizations).sort_by { |result| result['similarity'] }.last(MAXIMUM_RESULT_COUNT).reverse
    end
  end
end
