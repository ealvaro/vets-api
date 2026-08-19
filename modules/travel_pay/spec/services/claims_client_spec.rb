# frozen_string_literal: true

require 'rails_helper'

describe TravelPay::ClaimsClient do
  let(:user) { build(:user) }
  let(:auth_session) { TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token') }

  expected_log_prefix = 'travel_pay.claims.response_time'

  before do
    @stubs = Faraday::Adapter::Test::Stubs.new

    @conn = Faraday.new do |c|
      c.adapter(:test, @stubs)
      c.response :json
      c.request :json
    end

    allow(StatsD).to receive(:measure)
  end

  context 'prod settings' do
    it 'returns both subscription keys in headers' do
      headers =
        {
          'Content-Type' => 'application/json',
          'Ocp-Apim-Subscription-Key-E' => 'e_key',
          'Ocp-Apim-Subscription-Key-S' => 's_key'
        }

      with_settings(Settings, vsp_environment: 'production') do
        with_settings(Settings.travel_pay,
                      { subscription_key_e: 'e_key', subscription_key_s: 's_key' }) do
          expect(subject.send(:claim_headers)).to eq(headers)
        end
      end
    end
  end

  context '/claims' do
    # GET
    it 'returns response from claims endpoint' do
      allow_any_instance_of(TravelPay::ClaimsClient).to receive(:connection).and_return(@conn)
      @stubs.get('/api/v2/claims') do
        [
          200,
          {},
          {
            'totalRecordCount' => 3,
            'statusCode' => 200,
            'success' => true,
            'pageNumber' => 1,
            'pageSize' => 50,
            'message' => 'Successfully retrieved claims',
            'data' => [
              {
                'id' => 'uuid1',
                'claimNumber' => 'TC0000000000001',
                'claimStatus' => 'InProgress',
                'appointmentDateTime' => '2024-01-01T16:45:34.465Z',
                'facilityName' => 'Cheyenne VA Medical Center',
                'createdOn' => '2024-03-22T21:22:34.465Z',
                'modifiedOn' => '2024-01-01T16:44:34.465Z'
              },
              {
                'id' => 'uuid2',
                'claimNumber' => 'TC0000000000002',
                'claimStatus' => 'InProgress',
                'appointmentDateTime' => '2024-03-01T16:45:34.465Z',
                'facilityName' => 'Cheyenne VA Medical Center',
                'createdOn' => '2024-02-22T21:22:34.465Z',
                'modifiedOn' => '2024-03-01T00:00:00.0Z'
              },
              {
                'id' => 'uuid3',
                'claimNumber' => 'TC0000000000002',
                'claimStatus' => 'Incomplete',
                'appointmentDateTime' => '2024-02-01T16:45:34.465Z',
                'facilityName' => 'Cheyenne VA Medical Center',
                'createdOn' => '2024-01-22T21:22:34.465Z',
                'modifiedOn' => '2024-02-01T00:00:00.0Z'
              }
            ]
          }
        ]
      end

      expected_ids = %w[uuid1 uuid2 uuid3]

      client = TravelPay::ClaimsClient.new
      claims_response = client.get_claims(auth_session, {
                                            page_number: 1,
                                            page_size: 50
                                          })
      actual_claim_ids = claims_response.body['data'].pluck('id')

      expect(StatsD).to have_received(:measure)
        .with(expected_log_prefix,
              kind_of(Numeric),
              tags: ['travel_pay:get_all', 'status:success'])
      expect(actual_claim_ids).to eq(expected_ids)
    end

    it 'returns response from claims/:id endpoint' do
      allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_one_way_mileage, nil).and_return(false)
      allow_any_instance_of(TravelPay::ClaimsClient).to receive(:connection).and_return(@conn)
      @stubs.get('/api/v2/claims/uuid1') do
        [
          200,
          {},
          {
            'data' =>
              {
                'claimId' => 'uuid1',
                'claimNumber' => 'TC0000000000001',
                'claimName' => 'Claim created for NOLLE BARAKAT',
                'claimantFirstName' => 'Nolle',
                'claimantMiddleName' => 'Polite',
                'claimantLastName' => 'Barakat',
                'claimStatus' => 'PreApprovedForPayment',
                'appointmentDate' => '2024-01-01T16:45:34.465Z',
                'facilityName' => 'Cheyenne VA Medical Center',
                'totalCostRequested' => 20.00,
                'reimbursementAmount' => 14.52,
                'createdOn' => '2025-03-12T20:27:14.088Z',
                'modifiedOn' => '2025-03-12T20:27:14.088Z',
                'appointment' => {
                  'id' => '3fa85f64-5717-4562-b3fc-2c963f66afa6',
                  'appointmentSource' => 'API',
                  'appointmentDateTime' => '2024-01-01T16:45:34.465Z',
                  'appointmentType' => 'EnvironmentalHealth',
                  'facilityId' => '3fa85f64-5717-4562-b3fc-2c963f66afa6',
                  'facilityName' => 'Cheyenne VA Medical Center',
                  'serviceConnectedDisability' => 30,
                  'appointmentStatus' => 'Complete',
                  'externalAppointmentId' => '12345',
                  'associatedClaimId' => 'uuid1',
                  'associatedClaimNumber' => 'TC0000000000001',
                  'isCompleted' => true
                },
                'expenses' => [
                  {
                    'id' => '3fa85f64-5717-4562-b3fc-2c963f66afa6',
                    'expenseType' => 'Mileage',
                    'name' => '',
                    'dateIncurred' => '2024-01-01T16:45:34.465Z',
                    'description' => 'mileage-expense',
                    'costRequested' => 20.00,
                    'costSubmitted' => 20.00
                  }
                ]
              }
          }
        ]
      end

      expected_id = 'uuid1'

      client = TravelPay::ClaimsClient.new
      claims_response = client.get_claim_by_id(auth_session, 'uuid1')
      actual_claim = claims_response.body['data']

      expect(StatsD).to have_received(:measure)
        .with(expected_log_prefix,
              kind_of(Numeric),
              tags: ['travel_pay:get_by_id', 'status:success'])
      expect(actual_claim['claimId']).to eq(expected_id)
      expect(actual_claim['claimStatus']).to eq('PreApprovedForPayment')
      expect(actual_claim['expenses']).not_to be_empty
    end

    context 'when travel_pay_enable_one_way_mileage is enabled' do
      it 'calls the v4 claims endpoint' do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_one_way_mileage, user).and_return(true)
        allow_any_instance_of(TravelPay::ClaimsClient).to receive(:connection).and_return(@conn)

        @stubs.get('/api/v4/claims/uuid1') do
          [
            200,
            {},
            {
              'data' => {
                'claimId' => 'uuid1',
                'claimStatus' => 'InProgress',
                'expenses' => [
                  {
                    'id' => '3fa85f64-5717-4562-b3fc-2c963f66afa6',
                    'expenseType' => 'Mileage',
                    'startAddress' => '123 Main St, Springfield, VA 22150',
                    'endAddress' => '456 VA Medical Center Dr, Washington, DC 20422'
                  }
                ]
              }
            }
          ]
        end

        client = TravelPay::ClaimsClient.new(user)
        claims_response = client.get_claim_by_id(auth_session, 'uuid1')
        actual_claim = claims_response.body['data']

        expect(actual_claim['expenses'].first['startAddress']).to be_present
        expect(actual_claim['expenses'].first['endAddress']).to be_present
      end
    end

    context 'when travel_pay_enable_one_way_mileage is disabled' do
      it 'calls the v2 claims endpoint' do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_one_way_mileage, user).and_return(false)
        allow_any_instance_of(TravelPay::ClaimsClient).to receive(:connection).and_return(@conn)

        @stubs.get('/api/v2/claims/uuid1') do
          [
            200,
            {},
            {
              'data' => {
                'claimId' => 'uuid1',
                'claimStatus' => 'InProgress'
              }
            }
          ]
        end

        client = TravelPay::ClaimsClient.new(user)
        claims_response = client.get_claim_by_id(auth_session, 'uuid1')

        expect(claims_response.body['data']['claimId']).to eq('uuid1')
      end
    end

    it 'returns response from claims/search endpoint' do
      allow_any_instance_of(TravelPay::ClaimsClient).to receive(:connection).and_return(@conn)
      @stubs.get('api/v2/claims/search-by-appointment-date') do
        [
          200,
          {},
          { 'totalRecordCount' => 2,
            'statusCode' => 200,
            'success' => true,
            'pageNumber' => 1,
            'pageSize' => 50,
            'message' => 'Successfully retrieved claims',
            'data' => [
              {
                'id' => 'uuid1',
                'claimNumber' => 'TC0000000000001',
                'claimStatus' => 'InProgress',
                'appointmentDateTime' => '2024-01-01T16:45:34.465Z',
                'facilityName' => 'Cheyenne VA Medical Center',
                'createdOn' => '2024-03-22T21:22:34.465Z',
                'modifiedOn' => '2024-01-01T16:44:34.465Z'
              },
              {
                'id' => 'uuid3',
                'claimNumber' => 'TC0000000000002',
                'claimStatus' => 'Incomplete',
                'appointmentDateTime' => '2024-02-01T16:45:34.465Z',
                'facilityName' => 'Cheyenne VA Medical Center',
                'createdOn' => '2024-01-22T21:22:34.465Z',
                'modifiedOn' => '2024-02-01T00:00:00.0Z'
              }
            ] }
        ]
      end

      expected = %w[uuid1 uuid3]

      client = TravelPay::ClaimsClient.new
      claims_response = client.get_claims_by_date(auth_session,
                                                  { start_date: '2024-01-01T16:45:34.465Z',
                                                    end_date: '2024-02-01T16:45:34.465Z',
                                                    page_number: 1,
                                                    page_size: 50 })
      expect(claims_response.body['totalRecordCount']).to eq(claims_response.body['data'].size)
      actual_ids = claims_response.body['data'].pluck('id')

      expect(StatsD).to have_received(:measure)
        .with(expected_log_prefix,
              kind_of(Numeric),
              tags: ['travel_pay:get_by_date', 'status:success'])
      expect(actual_ids).to eq(expected)
    end

    # PATCH submit_claim
    it 'returns a claim ID from the claims endpoint' do
      allow_any_instance_of(TravelPay::ClaimsClient).to receive(:connection).and_return(@conn)
      claim_id = '3fa85f64-5717-4562-b3fc-2c963f66afa6'
      body = { 'appointmentId' => 'fake_btsss_appt_id', 'claimName' => 'SMOC claim',
               'claimantType' => 'Veteran' }.to_json
      @stubs.post('api/v2/claims') do
        [
          200,
          {},
          {
            'data' =>
              {
                'claimId' => claim_id
              }
          }
        ]
      end

      client = TravelPay::ClaimsClient.new
      new_claim_response = client.create_claim(auth_session, body)
      actual_claim_id = new_claim_response.body['data']['claimId']

      expect(StatsD).to have_received(:measure)
        .with(expected_log_prefix,
              kind_of(Numeric),
              tags: ['travel_pay:create', 'status:success'])
      expect(actual_claim_id).to eq(claim_id)
    end

    # PATCH submit_claim
    it 'returns a claim ID from the claims endpoint after submitting a claim' do
      claim_id = '3fa85f64-5717-4562-b3fc-2c963f66afa6'

      expect_any_instance_of(Faraday::Connection).to receive(:patch).with("api/v2/claims/#{claim_id}/submit")

      client = TravelPay::ClaimsClient.new
      client.submit_claim(auth_session, claim_id)
      expect(StatsD).to have_received(:measure)
        .with(expected_log_prefix,
              kind_of(Numeric),
              tags: ['travel_pay:submit', 'status:success'])
    end
  end
end
