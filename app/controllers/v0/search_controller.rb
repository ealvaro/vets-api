# frozen_string_literal: true

require 'search/pii_redactor'
require 'search/service'
require 'search_gsa/service'
require 'search_kendra/service'

module V0
  class SearchController < ApplicationController
    SEARCH_CACHE_GENERATION_KEY = 'search_results:generation'
    include ActionView::Helpers::SanitizeHelper
    service_tag 'search'

    skip_before_action :authenticate
    before_action :short_circuit_known_bots, only: :index
    before_action :load_user

    # Returns a page of search results, based on the passed query and page.
    #
    # Pagination schema follows precedent from other controllers that return pagination.
    # For example, the app/controllers/v0/prescriptions_controller.rb.
    #
    def index
      response = cached_results

      options = { meta: { pagination: response.pagination } }

      render json: SearchSerializer.new(response, options)
    end

    private

    # Returns an empty 204 response for requests coming from known crawlers/bots
    # (matched against a Parameter Store-configurable regex) so they never reach the
    # upstream search service. This protects the shared, rate-limited allowance
    # from being exhausted by automated traffic. Gated behind a Flipper
    # flag so it can be toggled without a deploy.
    #
    def short_circuit_known_bots
      return unless Flipper.enabled?(:search_skip_known_bots)

      pattern = bot_user_agent_pattern
      return if pattern.nil?

      user_agent = request.user_agent.to_s
      return unless user_agent.match?(pattern)

      Rails.logger.info(
        'V0::SearchController skipped upstream search for known bot',
        user_agent: Search::PiiRedactor.redact(user_agent)
      )

      head :no_content
    end

    # Compiles the configured bot User-Agent regex from Settings. The value is
    # sourced from Parameter Store (search__bot_user_agent_regex), so it
    # is treated as untrusted input: a blank or invalid pattern disables the
    # short-circuit rather than raising.
    #
    # @return [Regexp, nil]
    #
    def bot_user_agent_pattern
      raw = Settings.search&.bot_user_agent_regex
      return if raw.blank?

      unless raw.is_a?(String)
        Rails.logger.warn(
          'V0::SearchController bot_user_agent_regex must be a String; disabling known-bot short-circuit',
          value_class: raw.class.name
        )
        return
      end

      Regexp.new(raw, Regexp::IGNORECASE)
    rescue RegexpError => e
      Rails.logger.error("V0::SearchController invalid bot_user_agent_regex: #{e.message}")
      nil
    end

    # Returns the search results, using a read-through cache when the
    # :search_results_cache flag is enabled. Only successful responses are
    # cached (upstream errors raise before the block returns, so failures are
    # never stored). The raw response body is cached (a plain Hash) rather than
    # the response object to avoid coupling the cache to model internals.
    #
    # Emits api.search.results_cache with result:hit|miss|bypass and backend: tags.
    #
    # @return [Search::ResultsResponse]
    def cached_results
      unless Flipper.enabled?(:search_results_cache)
        StatsD.increment("#{Search::Service::STATSD_KEY_PREFIX}.results_cache",
                         tags: ['result:bypass', "backend:#{search_backend}"])
        return search_service.results
      end

      cache_hit = true
      body = Rails.cache.fetch(results_cache_key, expires_in: results_cache_ttl) do
        cache_hit = false
        search_service.results.body
      end

      StatsD.increment("#{Search::Service::STATSD_KEY_PREFIX}.results_cache",
                       tags: ["result:#{cache_hit ? 'hit' : 'miss'}", "backend:#{search_backend}"])

      Search::ResultsResponse.new(200, Search::ResultsResponse.pagination_object(body), body:)
    end

    # Cache key derived from the (sanitized) query, the upstream request offset,
    # and the active upstream backend. The query is hashed so raw user input is
    # never written to the cache key. Keying on the offset (via the same
    # Search::Pagination.offset_for the services use) keeps the cache aligned
    # with the actual upstream request: an omitted page, `page=0`, and `page=1`
    # all resolve to offset 0, and very high pages that clamp to the max offset
    # share one entry. The backend discriminator prevents an entry cached under
    # one search backend from being served after a backend flag flips
    # (multiple backends run concurrently during a cookie-based rollout).
    #
    # @return [String]
    def results_cache_key
      offset = Search::Pagination.offset_for(page)
      digest = Digest::SHA256.hexdigest("#{query}\x00#{offset}")
      "search_results:#{search_backend}:g#{cache_generation}:#{digest}"
    end

    # Generation token bumped by the nightly purge job. Read once per request and
    # memoized. A missing/never-purged key returns nil, which is a valid initial
    # bucket. Because the token is a wall-clock timestamp it only moves forward, so
    # a bumped generation is never reused and stale entries can't be resurrected.
    def cache_generation
      return @cache_generation if defined?(@cache_generation)

      @cache_generation = Rails.cache.read(SEARCH_CACHE_GENERATION_KEY)
    end

    # TTL for cached results, sourced from Settings so it can be tuned via
    # Param Store without a deploy. Falls back to 1 day when unset or invalid.
    # The nightly generation bump caps staleness to roughly 24 hours regardless
    # of this TTL.
    #
    # @return [Integer]
    def results_cache_ttl
      ttl = Settings.search&.results_cache_ttl_seconds.to_i
      ttl.positive? ? ttl : 1.day.to_i
    end

    def search_params
      params.permit(:query, :page)
    end

    def search_service
      @search_service ||= if kendra_backend?
                            SearchKendra::Service.new(query, page)
                          elsif v2_gsa_backend?
                            SearchGsa::Service.new(query, page)
                          else
                            Search::Service.new(query, page)
                          end
    end

    # Short token identifying the active upstream backend. Derived from the same
    # memoized flag check that selects the service, so the cache key can never
    # disagree with the backend that produced the body without instantiating a
    # service just to compute the key (which would run on cache hits too).
    #
    # @return [String]
    def search_backend
      return 'kendra' if kendra_backend?
      return 'gsa' if v2_gsa_backend?

      'default'
    end

    # Memoized decision for which upstream Search.gov backend to use. Single
    # source of truth shared by #search_service and #search_backend.
    #
    # @return [Boolean]
    def v2_gsa_backend?
      return @v2_gsa_backend if defined?(@v2_gsa_backend)

      @v2_gsa_backend = Flipper.enabled?(:search_use_v2_gsa)
    end

    # Memoized decision for whether to use Kendra as search backend.
    #
    # @return [Boolean]
    def kendra_backend?
      return @kendra_backend if defined?(@kendra_backend)

      @kendra_backend = Flipper.enabled?(:search_use_kendra, current_user)
    end

    # Returns a sanitized, permitted version of the passed query params.
    #
    # @return [String]
    # @see https://api.rubyonrails.org/v4.2/classes/ActionView/Helpers/SanitizeHelper.html#method-i-sanitize
    #
    def query
      sanitize search_params['query']
    end

    # This is the page (number) of results the FE is requesting to have returned.
    #
    # Returns a sanitized, permitted version of the passed page params. If 'page'
    # is not supplied, it returns nil.
    #
    # @return [String]
    # @return [NilClass]
    # @see https://api.rubyonrails.org/v4.2/classes/ActionView/Helpers/SanitizeHelper.html#method-i-sanitize
    #
    def page
      sanitize search_params['page']
    end
  end
end
