# frozen_string_literal: true

require 'rails_helper'

describe TravelPay::FacilitiesClient do
  let(:auth_session) do
    TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token', contact_id: 'contact-uuid-123')
  end
  let(:home_facility_id) { '975dae66-7833-e811-811f-1458d04e2938' }

  expected_log_prefix = 'travel_pay.facilities.response_time'

  before do
    @stubs = Faraday::Adapter::Test::Stubs.new

    @conn = Faraday.new do |c|
      c.adapter(:test, @stubs)
      c.response :json
      c.request :json
    end

    allow(StatsD).to receive(:measure)
  end

  context 'get_related_facilities' do
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

    it 'returns facilities from the related endpoint' do
      allow_any_instance_of(TravelPay::FacilitiesClient).to receive(:connection).and_return(@conn)
      @stubs.get("/api/v3/facilities/#{home_facility_id}/related") do
        [200, {}, facilities_body]
      end

      client = TravelPay::FacilitiesClient.new(auth_session)
      response = client.get_related_facilities(home_facility_id)

      expect(StatsD).to have_received(:measure)
        .with(expected_log_prefix,
              kind_of(Numeric),
              tags: ['travel_pay:get_related', 'status:success'])
      expect(response.body['data'].length).to eq(2)
      expect(response.body['data'].first['stationNumber']).to eq('983')
      expect(response.body['totalRecordCount']).to eq(2)
      expect(response.body['moreRecords']).to be(false)
    end

    it 'transforms snake_case query params to lowerCamelCase' do
      allow_any_instance_of(TravelPay::FacilitiesClient).to receive(:connection).and_return(@conn)
      @stubs.get("/api/v3/facilities/#{home_facility_id}/related") do
        [200, {}, facilities_body]
      end

      client = TravelPay::FacilitiesClient.new(auth_session)

      expect(@conn).to receive(:get)
        .with("api/v3/facilities/#{home_facility_id}/related",
              { 'pageNumber' => 1, 'pageSize' => 5, 'stationNumber' => '983' })
        .and_call_original

      client.get_related_facilities(home_facility_id, { page_number: 1, page_size: 5, station_number: '983' })
    end
  end
end
