# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Predictions::QuestionClassifiers::ServiceClient do
  let(:url) { 'http://localhost:8120' }
  let(:timeout) { 4 }

  let(:prediction_service) do
    Struct.new(:url, :timeout).new(url, timeout)
  end

  before do
    allow(Settings.ask_va_api).to receive(:prediction_service).and_return(prediction_service)
  end

  def capture_prediction_service_error
    yield
    nil
  rescue AskVAApi::Predictions::QuestionClassifiers::PredictionServiceError => e
    e
  end

  describe '#predict' do
    let(:service) { described_class.new }
    let(:predict_args) { { model_name: 'Category', question: 'Test question' } }
    let(:mock_response_body) do
      {
        'model_name' => 'Category',
        'model_version' => 2,
        'predictions' => {
          '1' => {
            'confidence_level' => 92,
            'name' => 'Education benefits',
            'model_id' => 1
          }
        }
      }
    end

    context 'with successful response' do
      it 'returns parsed response body' do
        stub_request(:post, /#{url}/)
          .to_return(status: 200, body: mock_response_body.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        result = service.predict(**predict_args)

        expect(result).to eq(mock_response_body)
      end

      it 'sends question and model name in request' do
        request_stub = stub_request(:post, /#{url}/)
                       .with(body: hash_including('question' => 'Test question', 'model_name' => 'Category'))
                       .to_return(status: 200, body: mock_response_body.to_json,
                                  headers: { 'Content-Type' => 'application/json' })

        service.predict(**predict_args)

        expect(request_stub).to have_been_requested
      end
    end

    context 'with validation error from service' do
      it 'raises PredictionServiceError with 422 status' do
        stub_request(:post, /#{url}/)
          .to_return(status: 422, body: { error: 'Invalid input' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(422)
      end
    end

    context 'with model not setup error' do
      it 'raises PredictionServiceError with 503 status' do
        stub_request(:post, /#{url}/)
          .to_return(status: 503, body: { error: 'Model not ready' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(503)
      end
    end

    context 'with timeout' do
      it 'raises PredictionServiceError with 504 status' do
        stub_request(:post, /#{url}/)
          .to_raise(Faraday::TimeoutError)

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(504)
      end
    end

    context 'with bad gateway from service' do
      it 'raises PredictionServiceError with 502 status' do
        stub_request(:post, /#{url}/)
          .to_return(status: 502, body: { error: 'Upstream timeout' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(502)
      end
    end

    context 'with gateway timeout from service' do
      it 'raises PredictionServiceError with 504 status' do
        stub_request(:post, /#{url}/)
          .to_return(status: 504, body: { error: 'Gateway timeout' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(504)
      end
    end

    context 'with connection error' do
      it 'raises PredictionServiceError with 502 status' do
        stub_request(:post, /#{url}/)
          .to_raise(Faraday::ConnectionFailed, 'Connection refused')

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(502)
      end
    end

    context 'with server error from service' do
      it 'raises PredictionServiceError with 502 status' do
        stub_request(:post, /#{url}/)
          .to_return(status: 500, body: { error: 'Internal server error' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(502)
      end
    end

    context 'with unauthorized error' do
      it 'raises PredictionServiceError with 401 status' do
        stub_request(:post, /#{url}/)
          .to_return(status: 401, body: { error: 'Unauthorized' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        error = capture_prediction_service_error { service.predict(**predict_args) }

        expect(error.status).to eq(401)
      end
    end
  end
end
