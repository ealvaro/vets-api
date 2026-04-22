# frozen_string_literal: true

require 'rails_helper'

describe 'VAOS V2 Slots', type: :request do
  let(:user) { build(:user, :vaos) }

  before do
    sign_in_as(user)
  end

  describe 'GET /vaos/v2/locations/:location_id/slots/next_available' do
    it 'returns next available slots' do
      expect_any_instance_of(VAOS::V2::SystemsService)
        .to receive(:get_next_available_slots)
        .with(
          hash_including(
            location_id: '983',
            clinic_ids: ['570'],
            before: '2026-04-30T23:59:59Z'
          )
        )
        .and_return(
          [
            OpenStruct.new(
              id: '570',
              clinic_id: '570',
              status: 'success',
              has_availability: true,
              slot_id: 'abc123',
              start: '2026-04-10T10:00:00Z',
              end: '2026-04-10T10:30:00Z'
            )
          ]
        )

      get '/vaos/v2/locations/983/slots/next_available',
          params: {
            clinic_ids: ['570'],
            before: '2026-04-30T23:59:59Z'
          }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body['data']).to be_present
      expect(body['data'][0]['id']).to eq('570')
      expect(body['data'][0]['type']).to eq('slots')
      expect(body['data'][0]['attributes']['clinic_id']).to eq('570')
      expect(body['data'][0]['attributes']['status']).to eq('success')
      expect(body['data'][0]['attributes']['has_availability']).to be(true)
      expect(body['data'][0]['attributes']['slot_id']).to eq('abc123')
      expect(body['data'][0]['attributes']['start']).to eq('2026-04-10T10:00:00Z')
      expect(body['data'][0]['attributes']['end']).to eq('2026-04-10T10:30:00Z')
    end

    it 'returns bad request when before is missing' do
      get '/vaos/v2/locations/983/slots/next_available',
          params: {
            clinic_ids: ['570']
          }

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns bad request when clinic_ids is missing' do
      get '/vaos/v2/locations/983/slots/next_available',
          params: {
            before: '2026-04-30T23:59:59Z'
          }

      expect(response).to have_http_status(:bad_request)
    end
  end
end
