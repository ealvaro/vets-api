# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AskVA Predictions API', type: :request do
  let(:user) { build(:user) }
  let(:mock_service_response) do
    {
      'model_name' => 'Category',
      'model_version' => '2',
      'predictions' => {
        '1' => {
          'confidence_level' => 92,
          'name' => 'Education benefits and work study',
          'model_id' => 1
        }
      }
    }
  end

  before do
    sign_in(user)
    allow(Flipper).to receive(:enabled?).with(:ask_va_predictive_category).and_return(true)
    allow_any_instance_of(AskVAApi::Predictions::QuestionClassifiers::ServiceClient)
      .to receive(:predict)
      .and_return(mock_service_response)
  end

  describe 'POST /ask_va_api/v0/predict/category' do
    let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

    context 'with valid question' do
      it 'returns 200 with predictions' do
        post('/ask_va_api/v0/predict/category',
             params: { question: 'How do I apply for education benefits?' }.to_json,
             headers:)

        expect(response).to have_http_status(:ok)
        expect(response_body['modelName']).to be_present
        expect(response_body['predictions']).to be_a(Hash)
        expect(response_body['predictions']['1']).to be_present
      end
    end

    context 'with missing question' do
      it 'returns 422 with error message' do
        post('/ask_va_api/v0/predict/category',
             params: {}.to_json,
             headers:)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response_body['error']['message']).to include('required')
      end
    end

    context 'with empty question' do
      it 'returns 422 with error message' do
        post('/ask_va_api/v0/predict/category',
             params: { question: '' }.to_json,
             headers:)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response_body['error']['message']).to include('required')
      end
    end

    context 'with question exceeding max length' do
      it 'returns 422 with error message' do
        long_question = 'a' * 10_001
        post('/ask_va_api/v0/predict/category',
             params: { question: long_question }.to_json,
             headers:)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response_body['error']['message']).to include('cannot exceed')
      end
    end

    context 'with HTML in question' do
      it 'sanitizes HTML before sending to service' do
        expect_any_instance_of(AskVAApi::Predictions::QuestionClassifiers::ServiceClient)
          .to receive(:predict)
          .with(model_name: 'Category', question: 'alert("xss")How do I apply?')
          .and_return(mock_service_response)

        post('/ask_va_api/v0/predict/category',
             params: { question: '<script>alert("xss")</script>How do I apply?' }.to_json,
             headers:)

        expect(response).to have_http_status(:ok)
        expect(response_body['modelName']).to be_present
      end
    end

    context 'when the feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:ask_va_predictive_category).and_return(false)
      end

      it 'returns 404' do
        post('/ask_va_api/v0/predict/category',
             params: { question: 'How do I apply for education benefits?' }.to_json,
             headers:)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  private

  def response_body
    JSON.parse(response.body)
  end
end
