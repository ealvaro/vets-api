# frozen_string_literal: true

require 'rails_helper'
require 'support/sm_client_helpers'
require 'support/shared_examples_for_mhv'

RSpec.describe 'MyHealth::V1::Messaging::Pact', type: :request do
  include SM::ClientHelpers

  let(:current_user) { build(:user, :mhv) }

  before do
    sign_in_as(current_user, stub_mhv_account: true)
    Timecop.freeze(Time.zone.parse('2017-05-01T19:25:00Z'))
  end

  after do
    Timecop.return
  end

  context 'when NOT authorized' do
    let(:current_user) { build(:user, :mhv, mhv_account_creation: { sm_account_created: false }) }

    before do
      get '/my_health/v1/messaging/pact/123'
    end

    include_examples 'for user account level', message: 'You do not have access to messaging'
  end

  context 'when authorized' do
    before do
      allow(SM::Client).to receive(:new).and_return(authenticated_client)
      VCR.insert_cassette('sm_client/session')
    end

    after do
      VCR.eject_cassette
    end

    describe '#show' do
      it 'returns an array of pcmm teams' do
        stations = %w[123 456]
        VCR.use_cassette('sm_client/pact/get_pacts') do
          get '/my_health/v1/messaging/pact'
        end
        expect(response).to be_successful
        expect(response.body).to be_a(String)
        response_json = JSON.parse(response.body)
        resp_stations = response_json['data'].map { |team| team.dig('attributes', 'station_number') }.uniq
        resp_team_name = response_json['data'].first.dig('attributes', 'team_name')
        expect(resp_stations).to match(stations.map(&:to_i))
        expect(resp_team_name).to match('Team 123')
      end
    end

    describe '#show_station' do
      it 'responds to GET #show_station' do
        station = '123'
        VCR.use_cassette('sm_client/pact/gets_a_pact') do
          get "/my_health/v1/messaging/pact/#{station}"
        end
        expect(response).to be_successful
        expect(response.body).to be_a(String)
        response_json = JSON.parse(response.body)
        resp_stations = response_json['data'].map { |team| team.dig('attributes', 'station_number') }.uniq
        resp_team_name = response_json['data'].first.dig('attributes', 'team_name')
        expect(resp_stations).to match([station.to_i])
        expect(resp_team_name).to match('Team 123')
      end

      context 'with an invalid station' do
        it 'handles missing station' do
          station = '999'
          VCR.use_cassette('sm_client/pact/gets_a_pact') do
            get "/my_health/v1/messaging/pact/#{station}"
          end
          expect(response).to be_successful
          expect(response.body).to be_a(String)
          response_json = JSON.parse(response.body)
          expect(response_json['data']).to be_empty
        end

        it 'handles non-integer station' do
          station = 'abc'
          VCR.use_cassette('sm_client/pact/gets_a_pact') do
            get "/my_health/v1/messaging/pact/#{station}"
          end
          expect(response).to have_http_status(:not_found)
          expect(response.body).to be_a(String)
          response_json = JSON.parse(response.body)
          expect(response_json['data']).to be_empty
        end
      end

      context 'when upstream returns an error' do
        it 'returns 502 when upstream returns a 500 error' do
          VCR.use_cassette('sm_client/pact/gets_a_pact_500') do
            get '/my_health/v1/messaging/pact/123'
          end

          expect(response).to have_http_status(:bad_gateway)
          result = JSON.parse(response.body)
          expect(result['errors'].first['code']).to eq('SM99')
        end
      end
    end
  end
end
