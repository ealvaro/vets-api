# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitsDiscovery::GatewayController, type: :request do
  let(:service_instance) { instance_double(BenefitsDiscovery::Service) }

  before do
    allow(StatsD).to receive(:increment)
    allow(BenefitsDiscovery::Service).to receive(:new).and_return(service_instance)
    allow(Flipper).to receive(:enabled?).with(:bds_gateway_enabled).and_return(true)
  end

  describe 'POST #recommendations' do
    let(:user) { build(:user, :loa3, icn: '1012345678V123456', birth_date: '1990-01-01') }
    let(:source_app_headers) { { 'Source-App-Name' => 'my-benefits-portal' } }
    let(:shared_api_key) { 'shared-api-key' }
    let(:shared_app_id) { 'shared-app-id' }
    let(:recommendations_response) do
      {
        'recommended' => [{
          'benefit_code' => 'HEALTH',
          'benefit_name' => 'Health',
          'benefit_url' => 'https://www.va.gov/health-care/'
        }],
        'not_recommended' => [{
          'benefit_code' => 'DU',
          'benefit_name' => 'Discharge Upgrade',
          'benefit_url' => 'https://www.va.gov/discharge-upgrade-instructions/introduction/'
        }],
        'undetermined' => []
      }
    end

    before do
      allow(Settings.lighthouse.benefits_discovery).to receive_messages(
        x_api_key: shared_api_key,
        x_app_id: shared_app_id
      )
      allow(BenefitsDiscovery::Service).to receive(:new).and_return(service_instance)
      allow(service_instance).to receive(:fetch_v1_recommendations).and_return(recommendations_response)
    end

    context 'with authenticated user and Source-App-Name header' do
      before { sign_in_as(user) }

      it 'returns successful response' do
        post '/benefits_discovery/v1/recommendations', headers: source_app_headers

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq(recommendations_response)
      end

      it 'uses shared credentials from settings' do
        expect(BenefitsDiscovery::Service).to receive(:new).with(
          api_key: shared_api_key,
          app_id: shared_app_id
        )

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end

      it 'calls fetch_v1_recommendations with user ICN and date of birth' do
        expect(service_instance).to receive(:fetch_v1_recommendations).with(
          icn: user.icn,
          date_of_birth: user.birth_date
        )

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end

      it 'increments StatsD request and success counters' do
        expect(StatsD).to receive(:increment).with('api.bds_gateway.proxy.request',
                                                   tags: ['path:benefits_discovery/v1/recommendations', 'method:POST'])
        expect(StatsD).to receive(:increment).with('api.bds_gateway.proxy.success',
                                                   tags: ['path:benefits_discovery/v1/recommendations', 'method:POST'])

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post '/benefits_discovery/v1/recommendations', headers: source_app_headers

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not call the service' do
        expect(BenefitsDiscovery::Service).not_to receive(:new)

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end
    end

    context 'without Source-App-Name header' do
      before { sign_in_as(user) }

      it 'returns unauthorized' do
        post '/benefits_discovery/v1/recommendations'

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not call the service' do
        expect(BenefitsDiscovery::Service).not_to receive(:new)

        post '/benefits_discovery/v1/recommendations'
      end
    end

    context 'when user has no ICN' do
      let(:user) { build(:user, :loa3, icn: nil) }

      before { sign_in_as(user) }

      it 'returns forbidden' do
        post '/benefits_discovery/v1/recommendations', headers: source_app_headers

        expect(response).to have_http_status(:forbidden)
      end

      it 'does not call the service' do
        expect(BenefitsDiscovery::Service).not_to receive(:new)

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end
    end

    context 'when service raises a ClientError' do
      before do
        sign_in_as(user)
        error = Common::Client::Errors::ClientError.new('BDS error', 503)
        allow(service_instance).to receive(:fetch_v1_recommendations).and_raise(error)
      end

      it 'returns the error status' do
        post '/benefits_discovery/v1/recommendations', headers: source_app_headers

        expect(response).to have_http_status(:service_unavailable)
      end

      it 'increments the error StatsD counter' do
        expect(StatsD).to receive(:increment).with('api.bds_gateway.proxy.error',
                                                   tags: array_including('path:benefits_discovery/v1/recommendations',
                                                                         'method:POST',
                                                                         'error:Common::Client::Errors::ClientError'))

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end
    end

    context 'when shared credentials are not configured' do
      before do
        sign_in_as(user)
        allow(Settings.lighthouse.benefits_discovery).to receive(:x_api_key).and_return(nil)
      end

      it 'returns service unavailable' do
        post '/benefits_discovery/v1/recommendations', headers: source_app_headers

        expect(response).to have_http_status(:service_unavailable)
      end

      it 'does not call the service' do
        expect(BenefitsDiscovery::Service).not_to receive(:new)

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end
    end

    context 'when service raises a StandardError' do
      before do
        sign_in_as(user)
        allow(service_instance).to receive(:fetch_v1_recommendations).and_raise(StandardError, 'Unexpected error')
      end

      it 'returns internal server error' do
        post '/benefits_discovery/v1/recommendations', headers: source_app_headers

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)).to have_key('errors')
      end

      it 'increments the error StatsD counter' do
        expect(StatsD).to receive(:increment).with('api.bds_gateway.proxy.error',
                                                   tags: array_including('path:benefits_discovery/v1/recommendations',
                                                                         'method:POST',
                                                                         'error:StandardError'))

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end
    end

    context 'when flipper is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:bds_gateway_enabled).and_return(false)
        sign_in_as(user)
      end

      it 'returns 404 not found' do
        post '/benefits_discovery/v1/recommendations', headers: source_app_headers

        expect(response).to have_http_status(:not_found)
      end

      it 'does not call the service' do
        expect(BenefitsDiscovery::Service).not_to receive(:new)

        post '/benefits_discovery/v1/recommendations', headers: source_app_headers
      end
    end
  end
end
