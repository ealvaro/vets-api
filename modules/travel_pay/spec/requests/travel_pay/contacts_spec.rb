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
  end
end
