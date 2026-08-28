# frozen_string_literal: true

require 'common/client/concerns/monitoring'
require 'common/exceptions/backend_service_exception'
require 'search/response'
require 'search/pagination'
require 'search/pii_redactor'
require 'search_kendra/configuration'
require 'search_kendra/query_normalizer'
require 'search_kendra/response_adapter'
require 'aws-sdk-kendra'

module SearchKendra
  # Wrapper around the Amazon Kendra Query API.
  # Calling {#results} returns a {Search::ResultsResponse} on success,
  # or raises an exception on failure.
  #
  # @see https://docs.aws.amazon.com/kendra/latest/APIReference/API_Query.html
  #
  class Service
    include Common::Client::Concerns::Monitoring

    STATSD_KEY_PREFIX = 'api.search'

    attr_reader :query, :page

    def initialize(query, page = 1)
      @query = query
      @page = page.to_i
    end

    # Fetches a page of search results from the Kendra Query API.
    #
    # @return [Search::ResultsResponse] wrapper around results data
    # @raise [Common::Exceptions::BackendServiceException] on upstream errors
    #
    def results
      with_monitoring do
        query_result = config.with_breakers { config.client.query(query_params) }.data
        kendra_response = SearchKendra::ResponseAdapter.new(query_result, processed_query, page_number)
        Search::ResultsResponse.from(kendra_response)
      end
    rescue => e
      handle_error(e)
    end

    private

    def config
      @config ||= SearchKendra::Configuration.instance
    end

    def query_params
      {
        document_relevance_override_configurations: config.relevance_tuning_config,
        index_id: config.index_id,
        page_number:,
        page_size:,
        query_text: processed_query
      }
    end

    def page_number
      [page, 1].max
    end

    def page_size
      Search::Pagination::ENTRIES_PER_PAGE
    end

    def processed_query
      normalized_query = SearchKendra::QueryNormalizer.normalize(query)
      Search::PiiRedactor.redact(normalized_query)
    end

    def handle_error(error)
      case error
      when Aws::Kendra::Errors::ThrottlingException
        handle_throttling!(error)
      when Aws::Kendra::Errors::ServiceError
        handle_service_error!(error)
      else
        raise error
      end
    end

    def handle_throttling!(error)
      StatsD.increment("#{STATSD_KEY_PREFIX}.exceptions", tags: ['exception:429'])
      handle_service_error!(error)
    end

    def handle_service_error!(error)
      code_name = error_code_name(error)
      save_error_details(code_name, error.message)
      raise_backend_exception(code_name, self.class, error)
    end

    def save_error_details(code_name, error_message)
      Rails.logger.error(
        'External service error',
        search: 'general_search_query_error',
        index_id: config.index_id,
        name: code_name,
        message: Search::PiiRedactor.redact(error_message.to_s)
      )
    end

    def error_code_name(error)
      "SEARCH_KENDRA_#{error.class.name.demodulize.upcase}"
    end

    def raise_backend_exception(key, source, error)
      raise Common::Exceptions::BackendServiceException.new(
        key,
        { source: source.to_s },
        nil,
        error.respond_to?(:message) ? error.message : error.to_s
      )
    end
  end
end
