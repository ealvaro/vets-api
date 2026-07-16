# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelPay::V0::ContactsController, type: :request do
  let(:user) { build(:user) }
  let(:auth_session) do
    TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token', contact_id: 'contact-uuid-123')
  end

  before do
    sign_in(user)
    allow_any_instance_of(TravelPay::AuthManager).to receive(:authorize).and_return(auth_session)
    allow(Flipper).to receive(:enabled?).with(:travel_pay_power_switch, instance_of(User)).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:travel_pay_unified_error_handling, instance_of(User)).and_return(true)
  end

  describe 'GET /travel_pay/v0/contact' do
    context 'when the contact is found' do
      let(:contact_body) do
        {
          'data' => {
            'id' => 'contact-uuid-123',
            'firstName' => 'John',
            'lastName' => 'Doe',
            'isVeteran' => true,
            'isCareGiver' => false
          }
        }
      end

      before do
        allow_any_instance_of(TravelPay::ContactClient).to receive(:get_contact)
          .and_return(Faraday::Response.new(status: 200, body: contact_body))
      end

      it 'returns 200 with contact data' do
        get '/travel_pay/v0/contact', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed['data']['id']).to eq('contact-uuid-123')
        expect(parsed['data']['firstName']).to eq('John')
        expect(parsed['data']['isVeteran']).to be(true)
      end
    end

    context 'when the service raises BackendServiceException' do
      before do
        allow_any_instance_of(TravelPay::ContactClient).to receive(:get_contact)
          .and_raise(Common::Exceptions::BackendServiceException.new(
                       'BTSSS-API_503', { status: 503, detail: 'Service unavailable' }, 503
                     ))
      end

      it 'returns structured error response' do
        get '/travel_pay/v0/contact', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['errors']).to be_present
      end
    end
  end

  context 'with unified error handling disabled (legacy)' do
    before do
      allow(Flipper).to receive(:enabled?).with(:travel_pay_unified_error_handling,
                                                instance_of(User)).and_return(false)
    end

    describe 'GET /travel_pay/v0/contact' do
      it 'uses legacy error handling for BackendServiceException' do
        allow_any_instance_of(TravelPay::ContactClient).to receive(:get_contact)
          .and_raise(Common::Exceptions::BackendServiceException.new(
                       nil, { status: 503, detail: 'Service unavailable' }, 503
                     ))

        get '/travel_pay/v0/contact', headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Error retrieving contact')
      end
    end
  end
end
