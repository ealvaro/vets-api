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

  context 'when the response body is not a Hash' do
    it 'does not raise an error' do
      env = env_for(status: 500, body: 'Internal Server Error')
      expect { middleware.on_complete(env) }.not_to raise_error
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

  context 'when the response body is nil' do
    it 'does not raise an error' do
      env = env_for(status: 500, body: nil)
      expect { middleware.on_complete(env) }.not_to raise_error
    end
  end
end
