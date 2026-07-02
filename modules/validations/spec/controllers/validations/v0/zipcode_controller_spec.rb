# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Validations::V0::ZipcodeController, type: :controller do
  routes { Validations::Engine.routes }

  describe 'GET #validate' do
    let(:validator_response) do
      {
        zip_is_valid: true,
        zipcode: '12345',
        message: 'Valid zipcode'
      }
    end

    it 'delegates to the zipcode validator and returns its response' do
      expect(Validations::Validator::ZipcodeValidator).to receive(:validate).with('12345')
                                                                            .and_return(validator_response)

      get :validate, params: { zipcode: '12345' }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        'zip_is_valid' => true,
        'zipcode' => '12345',
        'message' => 'Valid zipcode'
      )
    end

    it 'strips leading and trailing whitespace before validation' do
      expect(Validations::Validator::ZipcodeValidator).to receive(:validate).with('12345')
                                                                            .and_return(validator_response)

      get :validate, params: { zipcode: ' 12345 ' }

      expect(response).to have_http_status(:ok)
    end

    it 'allows access without authentication' do
      allow(Validations::Validator::ZipcodeValidator).to receive(:validate).and_return(validator_response)

      get :validate, params: { zipcode: '12345' }

      expect(response).to have_http_status(:ok)
    end
  end
end
