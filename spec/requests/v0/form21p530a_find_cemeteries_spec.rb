# frozen_string_literal: true

require 'rails_helper'
require 'form21p530a/find_cemeteries_service'

RSpec.describe 'V0::Form21p530aFindCemeteries', type: :request do
  include StatsD::Instrument::Helpers

  let(:user) { create(:user, :loa1) }

  let(:cemeteries_response) do
    [
      {
        org_nm: 'Arlington National Cemetery',
        addr_line_one: '1 Memorial Ave',
        addr_line_two: nil,
        city_nm: 'Arlington',
        state: 'VA',
        zip_code: '22211',
        day_phone_area_nbr: '703',
        day_phone_phone_nbr: '6071000'
      },
      {
        org_nm: 'Fort Logan National Cemetery',
        addr_line_one: '4400 W Kenyon Ave',
        addr_line_two: 'Suite 100',
        city_nm: 'Denver',
        state: 'CO',
        zip_code: '80236',
        day_phone_area_nbr: '303',
        day_phone_phone_nbr: '7611000'
      }
    ]
  end

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:form_530a_cemetery_prefill, anything).and_return(true)
  end

  describe 'GET /v0/form21p530a/cemeteries' do
    context 'when unauthenticated' do
      context 'when aquia_bio_auth_required is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:aquia_bio_auth_required, anything).and_return(true)
        end

        it 'returns 401 Unauthorized' do
          get '/v0/form21p530a/cemeteries'
          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'when aquia_bio_auth_required is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:aquia_bio_auth_required, anything).and_return(false)
          allow_any_instance_of(Form21p530a::FindCemeteriesService)
            .to receive(:response).and_return(cemeteries_response)
        end

        it 'allows unauthenticated access' do
          get '/v0/form21p530a/cemeteries'
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context 'when authenticated and feature flag is disabled' do
      before { sign_in_as(user) }

      it 'returns 404 Not Found' do
        allow(Flipper).to receive(:enabled?).with(:form_530a_cemetery_prefill, anything).and_return(false)
        get '/v0/form21p530a/cemeteries'
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when authenticated and feature flag is enabled' do
      before do
        sign_in_as(user)
        allow_any_instance_of(Form21p530a::FindCemeteriesService).to receive(:response).and_return(cemeteries_response)
      end

      it 'returns 200 OK' do
        get '/v0/form21p530a/cemeteries'
        expect(response).to have_http_status(:ok)
      end

      it 'returns cemeteries as a JSONAPI collection' do
        get '/v0/form21p530a/cemeteries'
        json = JSON.parse(response.body)
        expect(json['data']).to be_an(Array)
        expect(json['data'].length).to eq(2)
      end

      it 'serializes the correct FE-facing attributes' do
        get '/v0/form21p530a/cemeteries'
        attrs = JSON.parse(response.body)['data'].first['attributes']
        expect(attrs['name']).to eq('Arlington National Cemetery')
        expect(attrs['street']).to eq('1 Memorial Ave')
        expect(attrs['street2']).to be_nil
        expect(attrs['city']).to eq('Arlington')
        expect(attrs['state']).to eq('VA')
        expect(attrs['zip_code']).to eq('22211')
        expect(attrs['phone']).to eq('703-607-1000')
      end

      it 'includes street2 when present' do
        get '/v0/form21p530a/cemeteries'
        attrs = JSON.parse(response.body)['data'].second['attributes']
        expect(attrs['street2']).to eq('Suite 100')
      end

      it 'delegates to Form21p530a::FindCemeteriesService (cached)' do
        service_double = instance_double(Form21p530a::FindCemeteriesService, response: cemeteries_response)
        allow(Form21p530a::FindCemeteriesService).to receive(:new).and_return(service_double)

        get '/v0/form21p530a/cemeteries'

        expect(Form21p530a::FindCemeteriesService).to have_received(:new).once
        expect(service_double).to have_received(:response).once
      end
    end

    context 'when the service raises an error' do
      before do
        sign_in_as(user)
        allow_any_instance_of(Form21p530a::FindCemeteriesService)
          .to receive(:response)
          .and_raise(StandardError, 'BGS connection error')
      end

      it 'returns a 5xx status' do
        get '/v0/form21p530a/cemeteries'
        expect(response.status).to be >= 500
      end

      it 'increments the StatsD failure metric' do
        metrics = capture_statsd_calls do
          get '/v0/form21p530a/cemeteries'
        end

        expect(metrics.collect(&:name)).to include('api.form21p530a.find_cemeteries.failure')
      end
    end
  end
end
