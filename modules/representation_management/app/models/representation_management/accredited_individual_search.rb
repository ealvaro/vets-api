# frozen_string_literal: true

module RepresentationManagement
  class AccreditedIndividualSearch
    include ActiveModel::Model

    PERMITTED_MAX_DISTANCES = %w[5 10 25 50 100 200].freeze # in miles, no distance provided will default to "all"
    PERMITTED_MODEL_CLASSES = [AccreditedIndividual, Veteran::Service::Representative].freeze
    PERMITTED_SORTS = %w[distance_asc first_name_asc first_name_desc last_name_asc last_name_desc].freeze
    PERMITTED_TYPES = %w[attorney claims_agent representative].freeze

    attr_accessor :distance, :lat, :long, :model_class, :name, :org_name, :page, :per_page, :sort, :type

    validates :distance, inclusion: { in: PERMITTED_MAX_DISTANCES }, allow_nil: true
    validates :lat, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
    validates :long, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
    validates :model_class, presence: true, inclusion: { in: PERMITTED_MODEL_CLASSES }
    validates :page, numericality: { only_integer: true }, allow_nil: true
    validates :per_page, numericality: { only_integer: true }, allow_nil: true
    validates :sort, inclusion: { in: PERMITTED_SORTS }, allow_nil: true
    validates :type, presence: true, inclusion: { in: PERMITTED_TYPES }

    def perform
      query = base_query
      query = if distance.present?
                query.find_within_max_distance(long, lat, max_distance)
              else
                query.where.not(location: nil)
              end
      query = find_with_name(query) if name.present?
      query = find_with_org_name(query) if org_name.present? && type == 'representative'

      query
    end

    private

    def base_query
      if model_class == AccreditedIndividual
        query = model_class
                .includes(:active_accredited_organizations)
                .select('accredited_individuals.*', distance_query_string)
                .where(individual_type: type)
                .order(sort_query_string)
        # Representatives with no active accreditation have no organization to appoint through and
        # should not appear. Attorneys and claims agents have no accreditations by design.
        query = query.with_active_accreditation if type == AccreditedIndividual::INDIVIDUAL_TYPE_VSO_REPRESENTATIVE
        query
      else
        model_class
          .joins('JOIN LATERAL UNNEST(veteran_representatives.poa_codes) AS UnnestedPoaCode ON true')
          .joins('LEFT JOIN veteran_organizations ON UnnestedPoaCode = veteran_organizations.poa')
          .select('veteran_representatives.*', distance_query_string)
          .where(where_clause_for_veteran_type)
          .group(model_class.column_names.map { |col| "veteran_representatives.#{col}" })
          .order(sort_query_string)
      end
    end

    def distance_query_string
      ActiveRecord::Base
        .sanitize_sql_array([
                              'ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,' \
                              "#{model_class.table_name}.location) as distance",
                              long,
                              lat
                            ])
    end

    def sort_query_string
      case sort
      when 'first_name_asc' then 'first_name ASC'
      when 'first_name_desc' then 'first_name DESC'
      when 'last_name_asc' then 'last_name ASC'
      when 'last_name_desc' then 'last_name DESC'
      else
        distance_asc_string
      end
    end

    def distance_asc_string
      ActiveRecord::Base.sanitize_sql_for_order(
        [
          Arel.sql(
            "ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, #{model_class.table_name}.location) ASC"
          ),
          long,
          lat
        ]
      )
    end

    def find_with_name(query)
      if model_class == AccreditedIndividual
        query.find_with_full_name_similar_to(name)
      else
        find_veteran_with_name_similar_to(query)
      end
    end

    def find_with_org_name(query)
      if model_class == AccreditedIndividual
        query.left_joins(:active_accredited_organizations)
             .group('accredited_individuals.id')
             .having('? = ANY(ARRAY_AGG(accredited_organizations.name))', org_name)
      else
        query.having('? = ANY(ARRAY_AGG(veteran_organizations.name))', org_name)
      end
    end

    def max_distance
      AccreditedRepresentation::Constants::METERS_PER_MILE * Integer(distance)
    end

    # Veteran::Service::Representative-specific query methods
    def find_veteran_with_name_similar_to(query)
      query.where('word_similarity(?, veteran_representatives.full_name) >= ?',
                  name,
                  Veteran::Service::Constants::FUZZY_SEARCH_THRESHOLD)
    end

    def where_clause_for_veteran_type
      type_mappings = {
        'attorney' => 'attorney',
        'claims_agent' => 'claim_agents',
        'representative' => 'veteran_service_officer'
      }

      ['? = ANY(veteran_representatives.user_types)', type_mappings[type]]
    end
  end
end
