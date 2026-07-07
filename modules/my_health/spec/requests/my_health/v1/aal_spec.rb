# frozen_string_literal: true

require 'rails_helper'
require 'mhv/aal/client'
require 'support/mr_client_helpers'
require 'support/shared_examples_for_mhv'

RSpec.describe 'MyHealth::V1::AALController', type: :request do
  context 'Unauthorized user' do
    context 'with no MHV Correlation ID' do
      let(:user_id) { '21207668' }
      let(:current_user) { build(:user) }

      before do
        sign_in_as(current_user, stub_mhv_account: true)
      end

      it 'returns 403 Forbidden when MHV Correlation ID is missing' do
        post '/my_health/v1/aal'

        expect(current_user.mhv_correlation_id).to be_nil
        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['errors'].first['detail']).to eq('You do not have access to the AAL service')
      end
    end
  end

  context 'Authorized User' do
    let(:user_id) { '21207668' }
    let(:current_user) { build(:user, :mhv) }
    let(:valid_params) do
      {
        aal: {
          activity_type: 'Allergy',
          action: 'View',
          performer_type: 'Self',
          detail_value: nil,
          status: 1
        },
        product: 'mr'
      }
    end

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_enable_aal_integration).and_return(true)

      aal_client = AAL::MRClient.new(
        session: {
          user_id:,
          expires_at: 1.hour.from_now,
          token: '<SESSION_TOKEN>'
        }
      )

      allow(AAL::MRClient).to receive(:new).and_return(aal_client)
      sign_in_as(current_user, stub_mhv_account: true)
    end

    it 'responds to POST #create' do
      expect_any_instance_of(AAL::MRClient).to receive(:perform)
      VCR.use_cassette('phr_mgr_client/create_aal_entry') do
        post '/my_health/v1/aal', params: valid_params, as: :json
      end

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_a(String)
    end

    it 'fails on form validation' do
      invalid_params = valid_params.dup
      invalid_params[:aal] = invalid_params[:aal].merge(status: 3)

      post '/my_health/v1/aal', params: invalid_params, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to be_a(String)
    end

    it 'fails if product is missing' do
      invalid_params = valid_params.dup
      invalid_params.delete(:product)

      post '/my_health/v1/aal', params: invalid_params, as: :json

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json['errors'].first['detail']).to eq('The required parameter "product", is missing')
    end

    it 'fails if product is unknown' do
      post '/my_health/v1/aal', params: { product: 'unknown' }, as: :json

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json['errors'].first['detail']).to eq('Unknown product: unknown')
    end

    it 'skips the HTTP call with the flag off' do
      allow(Flipper).to receive(:enabled?).with(:mhv_enable_aal_integration).and_return(false)
      expect_any_instance_of(AAL::MRClient).not_to receive(:perform)

      post '/my_health/v1/aal', params: valid_params, as: :json

      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'GET /my_health/v1/aal (account activity log)' do
    let(:activities_response_body) do
      {
        'content' => [
          {
            'activityId' => 1,
            'userProfileId' => 12_345,
            'patientId' => 67_890,
            'action' => 'LOGIN',
            'status' => 'true',
            'performerType' => 'SELF',
            'activityType' => 'LOGIN_LOGOUT',
            'detailValue' => 'User logged in',
            'completionTime' => '2026-03-04T14:30:00Z'
          },
          {
            'activityId' => 2,
            'userProfileId' => 12_345,
            'patientId' => 67_890,
            'action' => 'VIEW_ALLERGY',
            'status' => 'true',
            'performerType' => 'SELF',
            'activityType' => 'ALLERGY',
            'detailValue' => nil,
            'completionTime' => '2026-03-04T14:35:00Z'
          }
        ],
        'pageable' => { 'pageNumber' => 0, 'pageSize' => 20 },
        'totalElements' => 2,
        'totalPages' => 1,
        'first' => true,
        'last' => true,
        'numberOfElements' => 2,
        'empty' => false
      }
    end

    context 'when the user has no MHV Correlation ID' do
      let(:current_user) { build(:user) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_account_activity_log_enabled, anything).and_return(true)
        sign_in_as(current_user, stub_mhv_account: true)
      end

      it 'returns 403 Forbidden and never authenticates the AAL client' do
        expect_any_instance_of(AAL::AALClient).not_to receive(:authenticate)

        get '/my_health/v1/aal'

        expect(current_user.mhv_correlation_id).to be_nil
        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['errors'].first['detail']).to eq('You do not have access to the AAL service')
      end
    end

    context 'when the feature toggle is disabled' do
      let(:current_user) { build(:user, :mhv) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_account_activity_log_enabled, anything).and_return(false)
        sign_in_as(current_user, stub_mhv_account: true)
      end

      it 'returns 403 Forbidden and never authenticates the AAL client' do
        expect_any_instance_of(AAL::AALClient).not_to receive(:authenticate)

        get '/my_health/v1/aal'

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['errors'].first['detail']).to eq('Account activity log feature is not enabled')
      end
    end

    context 'when the user is authorized and the feature is enabled' do
      let(:current_user) { build(:user, :mhv) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_account_activity_log_enabled, anything).and_return(true)
        sign_in_as(current_user, stub_mhv_account: true)
      end

      it 'authenticates the AAL client exactly once and returns paginated activity logs' do
        api_response = double('Faraday response', body: activities_response_body)
        allow_any_instance_of(AAL::AALClient).to receive(:get_activities).and_return(api_response)
        expect_any_instance_of(AAL::AALClient).to receive(:authenticate).once

        get '/my_health/v1/aal'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['data']).to be_an(Array)
        expect(json['data'].size).to eq(2)
        expect(json['data'].first['type']).to eq('activities')
        expect(json['data'].first['attributes']['action']).to eq('LOGIN')
        expect(json['data'].first['attributes']['activity_type']).to eq('LOGIN_LOGOUT')
        expect(json['data'].first['attributes']['performer_type']).to eq('SELF')
        expect(json['meta']['pagination']['total_elements']).to eq(2)
        expect(json['meta']['pagination']['page_number']).to eq(0)
      end

      it 'forwards the permitted query parameters to the client' do
        api_response = double('Faraday response', body: activities_response_body)
        allow_any_instance_of(AAL::AALClient).to receive(:authenticate)
        expect_any_instance_of(AAL::AALClient).to receive(:get_activities).with(
          ActionController::Parameters.new(
            'from_date' => 'Tuesday, 30 Apr 2024 04:00:00 GMT',
            'page' => '0',
            'limit' => '20'
          ).permit(:from_date, :to_date, :page, :limit, :sort, :select, :style)
        ).and_return(api_response)

        get '/my_health/v1/aal',
            params: { from_date: 'Tuesday, 30 Apr 2024 04:00:00 GMT', page: 0, limit: 20 }

        expect(response).to have_http_status(:ok)
      end

      it 'returns an empty data array when there are no activities' do
        empty_response_body = {
          'content' => [],
          'pageable' => { 'pageNumber' => 0, 'pageSize' => 20 },
          'totalElements' => 0,
          'totalPages' => 0,
          'first' => true,
          'last' => true,
          'numberOfElements' => 0,
          'empty' => true
        }
        api_response = double('Faraday response', body: empty_response_body)
        allow_any_instance_of(AAL::AALClient).to receive(:authenticate)
        allow_any_instance_of(AAL::AALClient).to receive(:get_activities).and_return(api_response)

        get '/my_health/v1/aal'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']).to eq([])
        expect(json['meta']['pagination']['total_elements']).to eq(0)
        expect(json['meta']['pagination']['empty_page']).to be(true)
      end
    end
  end
end
