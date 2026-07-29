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
  end
end

def pagination_for(response)
  body = JSON.parse response.body

  body.dig('meta', 'pagination')
end
