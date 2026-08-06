# frozen_string_literal: true

require 'rails_helper'

describe TravelPay::ContactClient do
  let(:auth_session) do
    TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token', contact_id: 'contact-uuid-123')
  end

  expected_log_prefix = 'travel_pay.contacts.response_time'

  before do
    @stubs = Faraday::Adapter::Test::Stubs.new

    @conn = Faraday.new do |c|
      c.adapter(:test, @stubs)
      c.response :json
      c.request :json
    end

    allow(StatsD).to receive(:measure)
  end

  context 'get_contact' do
    it 'returns response from contacts endpoint' do
      allow_any_instance_of(TravelPay::ContactClient).to receive(:connection).and_return(@conn)
      @stubs.get('/api/v3/contacts/contact-uuid-123') do
        [
          200,
          {},
          {
            'data' => {
              'id' => 'contact-uuid-123',
              'firstName' => 'John',
              'lastName' => 'Doe',
              'isVeteran' => true,
              'isCareGiver' => false
            }
          }
        ]
      end

      client = TravelPay::ContactClient.new(auth_session)
      contact_response = client.get_contact

      expect(StatsD).to have_received(:measure)
        .with(expected_log_prefix,
              kind_of(Numeric),
              tags: ['travel_pay:get_contact', 'status:success'])
      expect(contact_response.body['data']['id']).to eq('contact-uuid-123')
      expect(contact_response.body['data']['firstName']).to eq('John')
      expect(contact_response.body['data']['isVeteran']).to be(true)
    end
  end
end
