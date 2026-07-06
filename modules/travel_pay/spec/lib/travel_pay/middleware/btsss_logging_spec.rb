# frozen_string_literal: true

require 'rails_helper'
require 'travel_pay/middleware/btsss_logging'

RSpec.describe TravelPay::Middleware::BtsssLogging do
  let(:inner_app) { double('app') }
  let(:middleware) { described_class.new(inner_app) }

  let(:request_url) { URI('https://btsss.example.com/api/v2/appointments/find-or-add') }
  let(:request_headers) { { 'X-Correlation-ID' => 'abc-123' } }

  def build_env(method: :post, body: nil)
    env = Faraday::Env.new
    env.method = method
    env.url = request_url
    env.body = body
    env.request_headers = Faraday::Utils::Headers.new(request_headers)
    env
  end

  def build_response_env(env, status:, body:)
    env.status = status
    env[:body] = body
    env.response_headers = {}
    env
  end

  before do
    allow(Flipper).to receive(:enabled?).with(:travel_pay_btsss_logging).and_return(true)
  end

  describe '#call' do
    context 'when the response is successful (2xx)' do
      it 'logs at info level with scrubbed request and response bodies' do
        request_body = { 'appointmentDateTime' => '2024-01-01T12:00:00Z',
                         'facilityStationNumber' => '983' }.to_json

        response_body = {
          'data' => [{
            'id' => '123',
            'appointmentDateTime' => '2024-01-01T12:00:00Z',
            'facilityName' => 'VA Clinic',
            'status' => 'Submitted'
          }]
        }

        env = build_env(body: request_body)

        allow(inner_app).to receive(:call).with(env) do
          build_response_env(env, status: 200, body: response_body)
          Faraday::Response.new(env)
        end

        expect(Rails.logger).to receive(:info) do |msg, **tags|
          expect(msg).to eq('BTSSS service call succeeded')
          expect(tags[:service_name]).to eq('BTSSS-API')
          expect(tags[:http_method]).to eq('POST')
          expect(tags[:status]).to eq(200)
          expect(tags[:correlation_id]).to eq('abc-123')
          expect(tags[:request_body]).to include('appointmentDateTime' => '2024-01-01T12:00:00Z')
          expect(tags[:request_body]).to include('facilityStationNumber' => '983')
          expect(tags[:response_body]).to be_a(Hash)
        end

        middleware.call(env)
      end
    end

    context 'when the response is a 400 error' do
      it 'logs at warn level with scrubbed bodies' do
        request_body = { 'icn' => '1234567890V123456' }.to_json
        response_body = { 'message' => 'Validation failed' }

        env = build_env(body: request_body)

        allow(inner_app).to receive(:call).with(env) do
          build_response_env(env, status: 400, body: response_body)
          Faraday::Response.new(env)
        end

        expect(Rails.logger).to receive(:warn) do |msg, **tags|
          expect(msg).to eq('BTSSS service call failed')
          expect(tags[:status]).to eq(400)
          # ICN is intentionally preserved — it is needed for Datadog monitoring
          expect(tags[:request_body]['icn']).to eq('1234567890V123456')
          expect(tags[:response_body]).to be_a(Hash)
        end

        middleware.call(env)
      end
    end

    context 'when the response is a non-400 error' do
      it 'logs at warn level with scrubbed bodies' do
        response_body = { 'error' => 'Internal Server Error', 'status' => 500 }

        env = build_env(method: :get, body: nil)

        allow(inner_app).to receive(:call).with(env) do
          build_response_env(env, status: 500, body: response_body)
          Faraday::Response.new(env)
        end

        expect(Rails.logger).to receive(:warn) do |msg, **tags|
          expect(msg).to eq('BTSSS service call failed')
          expect(tags[:status]).to eq(500)
          expect(tags[:request_body]).to be_nil
          expect(tags[:response_body]).to eq({ 'error' => 'Internal Server Error', 'status' => 500 })
        end

        middleware.call(env)
      end
    end

    context 'when a timeout occurs' do
      it 'logs at warn level with nil bodies and re-raises' do
        env = build_env(body: nil)

        allow(inner_app).to receive(:call).and_raise(Faraday::TimeoutError)

        expect(Rails.logger).to receive(:warn) do |msg, **tags|
          expect(msg).to eq('BTSSS service call failed - Faraday::TimeoutError')
          expect(tags[:status]).to be_nil
          expect(tags[:request_body]).to be_nil
          expect(tags[:response_body]).to be_nil
        end

        expect { middleware.call(env) }.to raise_error(Faraday::TimeoutError)
      end
    end
  end

  describe 'PII scrubbing via DataScrubber' do
    it 'scrubs SSNs, emails, and phone numbers from response values (ICN is preserved)' do
      response_body = {
        'veteranContact' => {
          'ssn' => '123-45-6789',
          'email' => 'jane@example.com',
          'icn' => '1234567890V123456',
          'phone' => '555-123-4567'
        },
        'status' => 'Submitted',
        'id' => 'claim-uuid-safe'
      }

      env = build_env(body: nil)

      allow(inner_app).to receive(:call).with(env) do
        build_response_env(env, status: 200, body: response_body)
        Faraday::Response.new(env)
      end

      expect(Rails.logger).to receive(:info) do |_msg, tags|
        contact = tags[:response_body]['veteranContact']
        expect(contact['ssn']).to eq('[REDACTED]')
        expect(contact['email']).to eq('[REDACTED]')
        expect(contact['icn']).to eq('1234567890V123456') # ICN intentionally preserved for Datadog monitoring
        expect(contact['phone']).to eq('[REDACTED]')

        # Non-PII values pass through
        expect(tags[:response_body]['status']).to eq('Submitted')
        expect(tags[:response_body]['id']).to eq('claim-uuid-safe')
      end

      middleware.call(env)
    end

    it 'scrubs PII embedded in string values' do
      response_body = {
        'message' => 'Error processing claim for SSN 123-45-6789'
      }

      env = build_env(body: nil)

      allow(inner_app).to receive(:call).with(env) do
        build_response_env(env, status: 200, body: response_body)
        Faraday::Response.new(env)
      end

      expect(Rails.logger).to receive(:info) do |_msg, tags|
        expect(tags[:response_body]['message']).not_to include('123-45-6789')
        expect(tags[:response_body]['message']).to include('[REDACTED]')
      end

      middleware.call(env)
    end

    it 'scrubs PII in nested arrays' do
      response_body = {
        'data' => [
          { 'email' => 'vet1@example.com', 'status' => 'active' },
          { 'email' => 'vet2@example.com', 'status' => 'inactive' }
        ]
      }

      env = build_env(body: nil)

      allow(inner_app).to receive(:call).with(env) do
        build_response_env(env, status: 200, body: response_body)
        Faraday::Response.new(env)
      end

      expect(Rails.logger).to receive(:info) do |_msg, tags|
        data = tags[:response_body]['data']
        expect(data[0]['email']).to eq('[REDACTED]')
        expect(data[0]['status']).to eq('active')
        expect(data[1]['email']).to eq('[REDACTED]')
        expect(data[1]['status']).to eq('inactive')
      end

      middleware.call(env)
    end

    it 'preserves non-PII values' do
      response_body = {
        'appointmentDateTime' => '2024-06-15T10:00:00Z',
        'appointmentType' => 'CompensationAndPensionExamination',
        'facilityStationNumber' => '983',
        'isCompleted' => true,
        'currentStatus' => 'Submitted'
      }

      env = build_env(body: nil)

      allow(inner_app).to receive(:call).with(env) do
        build_response_env(env, status: 200, body: response_body)
        Faraday::Response.new(env)
      end

      expect(Rails.logger).to receive(:info) do |_msg, tags|
        body = tags[:response_body]
        expect(body['appointmentDateTime']).to eq('2024-06-15T10:00:00Z')
        expect(body['appointmentType']).to eq('CompensationAndPensionExamination')
        expect(body['facilityStationNumber']).to eq('983')
        expect(body['isCompleted']).to be(true)
        expect(body['currentStatus']).to eq('Submitted')
      end

      middleware.call(env)
    end

    it 'handles unparseable response bodies gracefully' do
      env = build_env(body: nil)

      allow(inner_app).to receive(:call).with(env) do
        build_response_env(env, status: 200, body: '<html>not json</html>')
        Faraday::Response.new(env)
      end

      expect(Rails.logger).to receive(:info) do |_msg, tags|
        expect(tags[:response_body]).to eq('[UNPARSEABLE]')
      end

      middleware.call(env)
    end

    it 'handles BTSSS validation error responses with string arrays in data' do
      response_body = {
        'correlationId' => 'abc-def-123',
        'timeStamp' => '2024-06-15T10:00:00Z',
        'statusCode' => 400,
        'message' => 'Bad Request',
        'success' => false,
        'data' => [
          'Validation Failed: The request parameters are missing or invalid.',
          'Validation Failed: The JSON value could not be converted to System.DateTime.' \
          'Path: $.appointmentDateTime | LineNumber: 1 | BytePositionInLine: 27.'
        ]
      }

      env = build_env(body: nil)

      allow(inner_app).to receive(:call).with(env) do
        build_response_env(env, status: 400, body: response_body)
        Faraday::Response.new(env)
      end

      expect(Rails.logger).to receive(:warn) do |msg, **tags|
        expect(msg).to eq('BTSSS service call failed')
        expect(tags[:status]).to eq(400)

        body = tags[:response_body]
        expect(body['correlationId']).to eq('abc-def-123')
        expect(body['statusCode']).to eq(400)
        expect(body['message']).to eq('Bad Request')
        expect(body['success']).to be(false)
        expect(body['data']).to be_an(Array)
        expect(body['data'].length).to eq(2)
        expect(body['data'][0]).to include('The request parameters are missing or invalid')
        expect(body['data'][1]).to include('The JSON value could not be converted')
      end

      middleware.call(env)
    end
  end
end
