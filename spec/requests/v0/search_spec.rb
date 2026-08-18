# frozen_string_literal: true

require 'rails_helper'
require 'support/error_details'

Rspec.describe 'V0::Search', type: :request do
  include SchemaMatchers
  include ErrorDetails

  let(:inflection_header) { { 'X-Key-Inflection' => 'camel' } }

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:search_use_v2_gsa).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:search_use_kendra, nil).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:search_results_cache).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:search_skip_known_bots).and_return(false)
  end

  describe 'GET /v0/search with known bot short-circuit' do
    let(:bot_headers) { { 'User-Agent' => 'Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)' } }
    let(:browser_headers) do
      { 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) ' \
                        'Chrome/120.0.0.0 Safari/537.36' }
    end

    context 'when the flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:search_skip_known_bots).and_return(true)
        allow(Settings.search).to receive(:bot_user_agent_regex).and_return('bingbot|Googlebot|crawler|spider')
      end

      it 'returns 204 and does not call the search service for a known bot User-Agent' do
        expect(Search::Service).not_to receive(:new)
        expect(SearchGsa::Service).not_to receive(:new)

        get '/v0/search', params: { query: 'benefits' }, headers: bot_headers

        expect(response).to have_http_status(:no_content)
      end

      it 'processes the request normally for a standard browser User-Agent' do
        VCR.use_cassette('search/success') do
          get '/v0/search', params: { query: 'benefits' }, headers: browser_headers

          expect(response).to have_http_status(:ok)
        end
      end

      it 'processes the request normally when the configured regex is blank' do
        allow(Settings.search).to receive(:bot_user_agent_regex).and_return('')

        VCR.use_cassette('search/success') do
          get '/v0/search', params: { query: 'benefits' }, headers: bot_headers

          expect(response).to have_http_status(:ok)
        end
      end
    end

    context 'when the flag is disabled' do
      before do
        allow(Settings.search).to receive(:bot_user_agent_regex).and_return('bingbot|Googlebot|crawler|spider')
      end

      it 'processes the request normally even for a known bot User-Agent' do
        VCR.use_cassette('search/success') do
          get '/v0/search', params: { query: 'benefits' }, headers: bot_headers

          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe 'GET /v0/search' do
    context 'with a 200 response' do
      it 'matches the search schema', :aggregate_failures do
        VCR.use_cassette('search/success') do
          get '/v0/search', params: { query: 'benefits' }

          expect(response).to have_http_status(:ok)
          expect(response).to match_response_schema('search')
        end
      end

      it 'matches the search schema when camel-inflected', :aggregate_failures do
        VCR.use_cassette('search/success') do
          get '/v0/search', params: { query: 'benefits' }, headers: inflection_header

          expect(response).to have_http_status(:ok)
          expect(response).to match_camelized_response_schema('search')
        end
      end

      it 'returns an array of hash search results in its body', :aggregate_failures do
        VCR.use_cassette('search/success') do
          get '/v0/search', params: { query: 'benefits' }

          body    = JSON.parse response.body
          results = body.dig('data', 'attributes', 'body', 'web', 'results')
          result  = results.first

          expect(results.class).to eq Array
          expect(result.class).to eq Hash
          expect(result.keys).to contain_exactly 'title', 'url', 'snippet', 'publication_date'
        end
      end
    end

    context 'with an empty query string' do
      it 'matches the errors schema', :aggregate_failures do
        VCR.use_cassette('search/empty_query') do
          get '/v0/search', params: { query: '' }

          expect(response).to have_http_status(:bad_request)
          expect(response).to match_response_schema('errors')
        end
      end

      it 'matches the errors schema when camel-inflected', :aggregate_failures do
        VCR.use_cassette('search/empty_query') do
          get '/v0/search', params: { query: '' }, headers: inflection_header

          expect(response).to have_http_status(:bad_request)
          expect(response).to match_camelized_response_schema('errors')
        end
      end
    end

    context 'with un-sanitized parameters' do
      it 'sanitizes the input, stripping all tags and attributes that are not allowlisted' do
        VCR.use_cassette('search/success') do
          dirty_params     = '<script>alert(document.cookie);</script>'
          sanitized_params = 'alert(document.cookie);'

          expect(Search::Service).to receive(:new).with(sanitized_params, '2')

          get '/v0/search', params: { query: dirty_params, page: 2 }
        end
      end
    end

    context 'with pagination' do
      let(:query_term) { 'benefits' }

      context "the endpoint's response" do
        it 'returns pagination meta data', :aggregate_failures do
          VCR.use_cassette('search/page_1') do
            get '/v0/search', params: { query: query_term, page: 1 }

            pagination = pagination_for(response)

            expect(pagination['current_page']).to be_present
            expect(pagination['per_page']).to be_present
            expect(pagination['total_pages']).to be_present
            expect(pagination['total_entries']).to be_present
          end
        end

        context 'when a specific page number is requested' do
          it 'current_page should be equal to the requested page number' do
            VCR.use_cassette('search/page_2') do
              get '/v0/search', params: { query: query_term, page: 2 }

              pagination = pagination_for(response)

              expect(pagination['current_page']).to eq 2
            end
          end
        end
      end

      context 'when the endpoint is being called' do
        context 'with a page' do
          it 'passes the page request to the search service object' do
            expect(Search::Service).to receive(:new).with(query_term, '2')

            get '/v0/search', params: { query: query_term, page: 2 }
          end
        end

        context 'with no page present' do
          it 'passes page=nil to the search service object' do
            expect(Search::Service).to receive(:new).with(query_term, nil)

            get '/v0/search', params: { query: query_term }
          end
        end
      end
    end

    context 'when upstream returns a 200 with a non-JSON body' do
      before do
        # Simulate Search.gov returning 200 with plain text (non-JSON content type).
        # Faraday's :json middleware skips parsing, leaving body as a String.
        # This exercises the full path: Service#results -> ResultsResponse.from -> Pagination.new
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: 'unexpected plain text response',
                     headers: { 'Content-Type' => 'text/plain' })
      end

      it 'does not raise a 500 error', :aggregate_failures do
        get '/v0/search', params: { query: 'benefits' }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        pagination = body.dig('meta', 'pagination')
        expect(pagination['total_entries']).to eq(0)
        expect(pagination['current_page']).to eq(0)
      end
    end

    context 'when Kendra is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:search_use_kendra, anything).and_return(true)
        Aws.config.update(credentials: Aws::Credentials.new('test-access-key', 'test-secret-key'))
      end

      context 'when not signed in' do
        it 'checks Flipper without current user' do
          VCR.use_cassette('search/kendra_success') do
            get '/v0/search', params: { query: 'benefits' }

            expect(Flipper).to have_received(:enabled?).with(:search_use_kendra, nil)
            expect(response).to have_http_status(:ok)
          end
        end

        it 'matches the search schema' do
          VCR.use_cassette('search/kendra_success') do
            get '/v0/search', params: { query: 'benefits' }

            expect(response).to have_http_status(:ok)
            expect(response).to match_response_schema('search')
          end
        end

        it 'passes the requested page to Kendra' do
          VCR.use_cassette('search/kendra_page_2') do
            get '/v0/search', params: {
              query: 'benefits',
              page: 2
            }

            expect(response).to have_http_status(:ok)
            expect(response).to match_response_schema('search')
          end
        end

        it 'handles Kendra errors', :aggregate_failures do
          VCR.use_cassette('search/kendra_error') do
            get '/v0/search', params: { query: 'benefits' }

            expect(response).to have_http_status(:bad_request)
            expect(response).to match_response_schema('errors')
          end
        end
      end

      context 'when signed in' do
        let(:user) { build(:user) }

        before { sign_in_as(user) }

        it 'checks Flipper for current user' do
          VCR.use_cassette('search/kendra_success') do
            get '/v0/search', params: { query: 'benefits' }

            expect(Flipper).to have_received(:enabled?).with(
              :search_use_kendra,
              an_object_having_attributes(flipper_id: user.flipper_id)
            )

            expect(response).to have_http_status(:ok)
          end
        end
      end
    end
  end

  describe 'GET /v0/search with results caching' do
    context 'when the :search_results_cache flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:search_results_cache).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:search_results_cache_purge).and_return(false)
        Rails.cache.clear
      end

      after { Rails.cache.clear }

      around do |example|
        original_store = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        example.run
      ensure
        Rails.cache = original_store
      end

      it 'calls the search service on a cache miss and serves the second identical request from cache' do
        VCR.use_cassette('search/success') do
          expect(Search::Service).to receive(:new).once.and_call_original

          get '/v0/search', params: { query: 'benefits' }
          expect(response).to have_http_status(:ok)
          first_body = response.body

          get '/v0/search', params: { query: 'benefits' }
          expect(response).to have_http_status(:ok)
          expect(response.body).to eq(first_body)
        end
      end

      it 'emits a miss metric on the first request and a hit metric on the second' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        allow(StatsD).to receive(:increment)

        get '/v0/search', params: { query: 'benefits' }
        get '/v0/search', params: { query: 'benefits' }

        expect(StatsD).to have_received(:increment)
          .with('api.search.results_cache', tags: ['result:miss', 'backend:default'])
          .once
        expect(StatsD).to have_received(:increment)
          .with('api.search.results_cache', tags: ['result:hit', 'backend:default'])
          .once
      end

      it 'includes the backend tag: default for the standard backend' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        allow(StatsD).to receive(:increment)

        get '/v0/search', params: { query: 'benefits' }

        expect(StatsD).to have_received(:increment)
          .with('api.search.results_cache', tags: array_including('backend:default'))
      end

      it 'includes the backend tag: gsa for the GSA backend' do
        allow(Flipper).to receive(:enabled?).with(:search_use_v2_gsa).and_return(true)
        stub_request(:get, /#{Settings.search_gsa.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        allow(StatsD).to receive(:increment)

        get '/v0/search', params: { query: 'benefits' }

        expect(StatsD).to have_received(:increment)
          .with('api.search.results_cache', tags: array_including('backend:gsa'))
      end

      it 'caches requests for different queries separately' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        expect(Search::Service).to receive(:new).twice.and_call_original

        get '/v0/search', params: { query: 'benefits' }
        get '/v0/search', params: { query: 'education' }

        expect(response).to have_http_status(:ok)
      end

      it 'caches different pages of the same query separately' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        expect(Search::Service).to receive(:new).twice.and_call_original

        get '/v0/search', params: { query: 'benefits', page: 1 }
        get '/v0/search', params: { query: 'benefits', page: 2 }

        expect(response).to have_http_status(:ok)
      end

      it 'treats an omitted page and page=1 as the same cache entry' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        # Both requests map to the first page upstream, so the service is only
        # instantiated once; the second request is served from cache.
        expect(Search::Service).to receive(:new).once.and_call_original

        get '/v0/search', params: { query: 'benefits' }
        get '/v0/search', params: { query: 'benefits', page: 1 }

        expect(response).to have_http_status(:ok)
      end

      it 'caches each upstream backend separately so a flag flip does not cross-serve results' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })
        stub_request(:get, /#{Settings.search_gsa.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        # Same query and page, but each backend is a distinct upstream, so each
        # must produce its own cache entry rather than reusing the other's.
        allow(Flipper).to receive(:enabled?).with(:search_use_v2_gsa).and_return(false)
        expect(Search::Service).to receive(:new).once.and_call_original
        get '/v0/search', params: { query: 'benefits' }

        allow(Flipper).to receive(:enabled?).with(:search_use_v2_gsa).and_return(true)
        expect(SearchGsa::Service).to receive(:new).once.and_call_original
        get '/v0/search', params: { query: 'benefits' }

        expect(response).to have_http_status(:ok)
      end

      it 'treats a bumped generation as a cache miss (invalidation)' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        # Warm the cache
        expect(Search::Service).to receive(:new).twice.and_call_original

        get '/v0/search', params: { query: 'benefits' }

        # Bump the generation — simulates the nightly purge job
        Rails.cache.write(V0::SearchController::SEARCH_CACHE_GENERATION_KEY, Time.current.to_i + 1)

        # Same query must now miss (new key due to new generation)
        get '/v0/search', params: { query: 'benefits' }

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when the :search_results_cache flag is disabled' do
      it 'calls the search service for every request' do
        VCR.use_cassette('search/success') do
          expect(Search::Service).to receive(:new).twice.and_call_original

          get '/v0/search', params: { query: 'benefits' }
          get '/v0/search', params: { query: 'benefits' }
        end
      end

      it 'emits a bypass metric' do
        stub_request(:get, /#{Settings.search.url}/)
          .to_return(status: 200, body: '{"web":{"results":[]}}',
                     headers: { 'Content-Type' => 'application/json' })

        allow(StatsD).to receive(:increment)

        get '/v0/search', params: { query: 'benefits' }

        expect(StatsD).to have_received(:increment)
          .with('api.search.results_cache', tags: ['result:bypass', 'backend:default'])
      end
    end
  end
end

def pagination_for(response)
  body = JSON.parse response.body

  body.dig('meta', 'pagination')
end
