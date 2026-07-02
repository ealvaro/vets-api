# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Validations::V0::Zipcode', type: :request do
  let(:state) { create(:std_state) }

  describe 'GET /validations/v0/zipcode/:zipcode' do
    context 'with a valid 5-digit zipcode' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '12345', state_id: state.id) }

      it 'returns valid response' do
        get '/validations/v0/zipcode/12345'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(true)
        expect(json_response['zipcode']).to eq('12345')
        expect(json_response['message']).to eq('Valid zipcode')
      end
    end

    context 'with a valid ZIP+4 format' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '12345', state_id: state.id) }

      it 'returns valid response' do
        get '/validations/v0/zipcode/12345-6789'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(true)
        expect(json_response['zipcode']).to eq('12345-6789')
        expect(json_response['message']).to eq('Valid zipcode')
      end
    end

    context 'with an Invalid zipcode' do
      it 'returns invalid response' do
        get '/validations/v0/zipcode/ABCDE'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(false)
        expect(json_response['message']).to eq('Invalid zipcode')
      end
    end

    context 'with too few digits' do
      it 'returns invalid response' do
        get '/validations/v0/zipcode/1234'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(false)
        expect(json_response['message']).to eq('Invalid zipcode')
      end
    end

    context 'with too many digits' do
      it 'returns invalid response' do
        get '/validations/v0/zipcode/123456'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(false)
        expect(json_response['message']).to eq('Invalid zipcode')
      end
    end

    context 'with special characters' do
      it 'returns invalid response' do
        get '/validations/v0/zipcode/12@45'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(false)
        expect(json_response['message']).to eq('Invalid zipcode')
      end
    end

    context 'with zipcode not in database' do
      it 'returns invalid response' do
        get '/validations/v0/zipcode/99999'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(false)
        expect(json_response['message']).to eq('Zipcode does not exist')
      end
    end

    context 'with leading/trailing whitespace' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '54321', state_id: state.id) }

      it 'strips whitespace before validation' do
        get '/validations/v0/zipcode/%2054321%20'

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['zip_is_valid']).to be(true)
        expect(json_response['zipcode']).to eq('54321')
        expect(json_response['message']).to eq('Valid zipcode')
      end
    end
  end
end
