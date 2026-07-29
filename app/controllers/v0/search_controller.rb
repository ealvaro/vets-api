# frozen_string_literal: true

require 'search/pii_redactor'
require 'search/service'
require 'search_gsa/service'

module V0
  class SearchController < ApplicationController
    include ActionView::Helpers::SanitizeHelper
    service_tag 'search'

    skip_before_action :authenticate
    before_action :short_circuit_known_bots, only: :index

    # Returns a page of search results from the Search.gov API, based on the passed query and page.
    #
    # Pagination schema follows precedent from other controllers that return pagination.
    # For example, the app/controllers/v0/prescriptions_controller.rb.
    #
    def index
      response = search_service.results
      options = { meta: { pagination: response.pagination } }

      render json: SearchSerializer.new(response, options)
    end

    private

    # Returns an empty 204 response for requests coming from known crawlers/bots
    # (matched against a Parameter Store-configurable regex) so they never reach the
    # upstream Search.gov API. This protects the shared, rate-limited Search.gov
    # allowance from being exhausted by automated traffic. Gated behind a Flipper
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

    def search_params
      params.permit(:query, :page)
    end

    def search_service
      @search_service ||= if Flipper.enabled?(:search_use_v2_gsa)
                            SearchGsa::Service.new(query, page)
                          else
                            Search::Service.new(query, page)
                          end
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
