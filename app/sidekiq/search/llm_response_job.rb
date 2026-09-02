# frozen_string_literal: true

require 'aws-sdk-bedrockruntime'
require 'search_llm/cache'

module Search
  class LlmResponseJob
    include Sidekiq::Job

    STATSD_KEY_PREFIX = 'api.search.llm_response_job'
    sidekiq_options retry: 3

    def perform(search_id, query, results)
      return unless Flipper.enabled?(:search_generate_llm_response)

      response = generate_response(query, results)
      handle_success(search_id, response) if response
    rescue => e
      handle_error(search_id, e)
      raise
    end

    private

    def generate_response(query, results)
      client = Aws::BedrockRuntime::Client.new(region: Settings.search_llm.region)

      response = client.converse(
        model_id: Settings.search_llm.prompt_arn,
        prompt_variables: {
          query: { text: query },
          results: { text: format_results(results) }
        }
      )

      response.output.message.content
              .filter_map { |content| content.text if content.respond_to?(:text) }
              .join
              .presence
    end

    def format_results(results)
      results.map.with_index(1) do |result, index|
        {
          number: index,
          title: result[:title],
          url: result[:url],
          excerpt: result[:excerpt]
        }
      end.to_json
    end

    def handle_success(search_id, response)
      Rails.cache.write(
        SearchLlm::Cache.key(search_id),
        response,
        expires_in: 6.hours
      )
      StatsD.increment("#{STATSD_KEY_PREFIX}.success")
    end

    def handle_error(search_id, error)
      StatsD.increment("#{STATSD_KEY_PREFIX}.error")
      Rails.logger.error(
        'SearchLlm::ResponseJob failed',
        error_class: error.class.name,
        error_message: error.message,
        search_id:
      )
    end
  end
end
