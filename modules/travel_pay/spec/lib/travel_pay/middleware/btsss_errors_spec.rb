# frozen_string_literal: true

require 'rails_helper'
require 'travel_pay/middleware/btsss_errors'

RSpec.describe TravelPay::Middleware::BtsssErrors do
  let(:app) { double('app') }
  let(:middleware) { described_class.new(app) }

  def env_for(status:, body:)
    env = Faraday::Env.new
    env.status = status
    env[:body] = body
    env
  end

  context 'when the response is successful' do
    it 'does not modify the body' do
      body = { 'message' => 'All good', 'statusCode' => 200 }
      env = env_for(status: 200, body:)
      middleware.on_complete(env)
      expect(env[:body]).to eq({ 'message' => 'All good', 'statusCode' => 200 })
    end
  end

  context 'when the response is an error with BTSSS format' do
    it 'normalizes message to detail and statusCode to code' do
      body = {
        'correlationId' => 'abc-123',
        'timeStamp' => '2025-09-15T22:32:38Z',
        'statusCode' => 400,
        'message' => 'Validation failed: The claim does not have any expenses.',
        'success' => false,
        'data' => nil
      }
      env = env_for(status: 400, body:)
      middleware.on_complete(env)

      expect(env[:body]['detail']).to eq('Validation failed: The claim does not have any expenses.')
      expect(env[:body]['code']).to eq('400')
      expect(env[:body]['message']).to eq('Validation failed: The claim does not have any expenses.')
      expect(env[:body]['statusCode']).to eq(400)
    end
  end

  context 'when the response has validation messages in the data array' do
    it 'combines message and data array into detail' do
      body = {
        'correlationId' => 'abc-def-123',
        'timeStamp' => '2025-09-15T22:32:38Z',
        'statusCode' => 400,
        'message' => 'Bad Request',
        'success' => false,
        'data' => [
          'Validation Failed: The request parameters are missing or invalid.',
          'Validation Failed: The JSON value could not be converted to System.DateTime. ' \
          'Path: $.appointmentDateTime | LineNumber: 1 | BytePositionInLine: 27.'
        ]
      }
      env = env_for(status: 400, body:)
      middleware.on_complete(env)

      expect(env[:body]['detail']).to eq(
        'Bad Request: Validation Failed: The request parameters are missing or invalid.; ' \
        'Validation Failed: The JSON value could not be converted to System.DateTime. ' \
        'Path: $.appointmentDateTime | LineNumber: 1 | BytePositionInLine: 27.'
      )
      expect(env[:body]['code']).to eq('400')
    end

    it 'ignores non-string items in the data array' do
      body = {
        'statusCode' => 400,
        'message' => 'Bad Request',
        'success' => false,
        'data' => [
          'Validation Failed: Missing field.',
          42,
          nil,
          { 'nested' => 'object' }
        ]
      }
      env = env_for(status: 400, body:)
      middleware.on_complete(env)

      expect(env[:body]['detail']).to eq('Bad Request: Validation Failed: Missing field.')
    end
  end

  context 'when the response body is not a Hash' do
    it 'does not raise an error' do
      env = env_for(status: 500, body: 'Internal Server Error')
      expect { middleware.on_complete(env) }.not_to raise_error
    end

    it 'converts a string body to a Hash with detail and code' do
      env = env_for(status: 502, body: '<html>Bad Gateway</html>')
      middleware.on_complete(env)

      expect(env[:body]).to be_a(Hash)
      expect(env[:body]['detail']).to eq('<html>Bad Gateway</html>')
      expect(env[:body]['code']).to eq('502')
    end

    it 'converts a string body for 503 errors' do
      env = env_for(status: 503, body: 'Service Unavailable')
      middleware.on_complete(env)

      expect(env[:body]).to be_a(Hash)
      expect(env[:body]['detail']).to eq('Service Unavailable')
      expect(env[:body]['code']).to eq('503')
    end

    it 'truncates long non-JSON bodies to 200 characters' do
      long_body = 'x' * 500
      env = env_for(status: 502, body: long_body)
      middleware.on_complete(env)

      expect(env[:body]['detail'].length).to be <= 200
    end
  end

  context 'when the response body is nil' do
    it 'converts nil body to a Hash with detail and code' do
      env = env_for(status: 500, body: nil)
      middleware.on_complete(env)

      expect(env[:body]).to be_a(Hash)
      expect(env[:body]['detail']).to eq('')
      expect(env[:body]['code']).to eq('500')
    end
  end

  context 'when the response body has no message or statusCode' do
    it 'does not modify the body' do
      body = { 'error' => 'something else' }
      env = env_for(status: 400, body:)
      middleware.on_complete(env)
      expect(env[:body]).to eq({ 'error' => 'something else' })
    end
  end
end
