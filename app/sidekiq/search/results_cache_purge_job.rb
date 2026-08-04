# frozen_string_literal: true

module Search
  class ResultsCachePurgeJob
    include Sidekiq::Job

    STATSD_KEY_PREFIX = 'api.search.results_cache_purge'

    sidekiq_options retry: 3

    sidekiq_retries_exhausted do |msg, _ex|
      StatsD.increment("#{STATSD_KEY_PREFIX}.exhausted")
      Rails.logger.error(
        'Search::ResultsCachePurgeJob exhausted',
        job_id: msg['jid'], error_class: msg['error_class'], error_message: msg['error_message']
      )
    end

    def perform
      return unless Flipper.enabled?(:search_results_cache_purge)

      generation = Time.current.to_i
      # No expiry: the control key must persist so the generation is stable
      # between nightly runs.
      Rails.cache.write(V0::SearchController::SEARCH_CACHE_GENERATION_KEY, generation, expires_in: nil)

      StatsD.increment("#{STATSD_KEY_PREFIX}.success")
      StatsD.gauge("#{STATSD_KEY_PREFIX}.generation", generation)
      Rails.logger.info('Search::ResultsCachePurgeJob bumped search cache generation', generation:)
    rescue => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.error")
      Rails.logger.error('Search::ResultsCachePurgeJob failed', error_class: e.class.name, error_message: e.message)
      raise
    end
  end
end
