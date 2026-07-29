# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelPay::V0::FacilitiesController, type: :request do
  let(:user) { build(:user) }
  let(:auth_session) do
    TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token', contact_id: 'contact-uuid-123')
  end
  let(:home_facility_id) { '975dae66-7833-e811-811f-1458d04e2938' }
  let(:contact_body) do
    {
      'correlationId' => 'some-correlation-id',
      'statusCode' => 200,
      'success' => true,
      'data' => {
        'id' => 'contact-uuid-123',
        'firstName' => 'NOLLE',
        'lastName' => 'BARAKAT',
        'isVeteran' => true,
        'isCareGiver' => false,
        'homeFacility' => {
          'id' => home_facility_id,
          'name' => 'Cheyenne VA Medical Center Test',
          'stationNumber' => '983',
          'city' => 'CHEYENNE',
          'stateOrProvince' => 'WY'
        }
      }
    }
  end

  before do
    sign_in(user)
    allow(Flipper).to receive(:enabled?).with(:travel_pay_power_switch, instance_of(User)).and_return(true)
    allow(Flipper).to receive(:enabled?)
      .with(:travel_pay_enable_user_created_appointments, instance_of(User)).and_return(true)
    allow_any_instance_of(TravelPay::AuthManager).to receive(:authorize).and_return(auth_session)
    allow_any_instance_of(TravelPay::ContactClient).to receive(:get_contact)
      .and_return(Faraday::Response.new(status: 200, body: contact_body))
  end

  describe 'GET /travel_pay/v0/facilities/related' do
    context 'when travel_pay_enable_user_created_appointments feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:travel_pay_enable_user_created_appointments, instance_of(User)).and_return(false)
      end

      it 'returns 503 service unavailable' do
        get '/travel_pay/v0/facilities/related', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when facilities are returned successfully' do
      let(:facilities_body) do
        {
          'correlationId' => 'some-correlation-id',
          'statusCode' => 0,
          'success' => true,
          'data' => [
            {
              'id' => home_facility_id,
              'name' => 'Cheyenne VA Medical Center Test',
              'stationNumber' => '983',
              'city' => 'CHEYENNE',
              'stateOrProvince' => 'WY'
            },
            {
              'id' => 'abc12345-1234-1234-1234-abcdef012345',
              'name' => 'Cheyenne Community Clinic',
              'stationNumber' => '983GC',
              'city' => 'CHEYENNE',
              'stateOrProvince' => 'WY'
            }
          ],
          'pageNumber' => 1,
          'pageSize' => 10,
          'totalRecordCount' => 2,
          'moreRecords' => false
        }
      end

      before do
        allow_any_instance_of(TravelPay::FacilitiesClient).to receive(:get_related_facilities)
          .with(home_facility_id, anything)
          .and_return(Faraday::Response.new(status: 200, body: facilities_body))
      end

      it 'returns 200 with facilities data' do
        get '/travel_pay/v0/facilities/related', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed['data'].length).to eq(2)
        expect(parsed['data'].first['stationNumber']).to eq('983')
      end
    end

    context 'when the contact has no home facility' do
      let(:contact_body_no_facility) do
        {
          'correlationId' => 'some-correlation-id',
          'statusCode' => 200,
          'success' => true,
          'data' => {
            'id' => 'contact-uuid-123',
            'firstName' => 'NOLLE',
            'lastName' => 'BARAKAT',
            'isVeteran' => true,
            'isCareGiver' => false,
            'homeFacility' => nil
          }
        }
      end

      before do
        allow_any_instance_of(TravelPay::ContactClient).to receive(:get_contact)
          .and_return(Faraday::Response.new(status: 200, body: contact_body_no_facility))
      end

      it 'returns 404' do
        get '/travel_pay/v0/facilities/related', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:not_found)
        parsed = JSON.parse(response.body)
        expect(parsed['error']).to eq('No home facility found for this user')
      end
    end

    context 'when the contact call fails' do
      before do
        allow_any_instance_of(TravelPay::ContactClient).to receive(:get_contact)
          .and_raise(Common::Exceptions::BackendServiceException.new('BTSSS-API_503', { status: 503 }, 503))
      end

      it 'returns an error response' do
        get '/travel_pay/v0/facilities/related', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:service_unavailable)
        parsed = JSON.parse(response.body)
        expect(parsed['errors']).to be_present
        expect(parsed['errors'].first).to have_key('code')
      end
    end

    context 'when the facilities call fails' do
      before do
        allow_any_instance_of(TravelPay::FacilitiesClient).to receive(:get_related_facilities)
          .and_raise(Common::Exceptions::BackendServiceException.new('BTSSS-API_502', { status: 502 }, 502))
      end

      it 'returns an error response' do
        get '/travel_pay/v0/facilities/related', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:bad_gateway)
        parsed = JSON.parse(response.body)
        expect(parsed['errors']).to be_present
        expect(parsed['errors'].first).to have_key('code')
      end
    end

    context 'when a connection-level error occurs' do
      before do
        allow_any_instance_of(TravelPay::FacilitiesClient).to receive(:get_related_facilities)
          .and_raise(Faraday::TimeoutError)
      end

      it 'returns a 504 timeout error' do
        get '/travel_pay/v0/facilities/related', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:gateway_timeout)
        parsed = JSON.parse(response.body)
        expect(parsed['errors']).to be_present
        expect(parsed['errors'].first['code']).to eq('BTSSS-API_CONNECTION_TIMEOUT')
      end
    end
  end
end
