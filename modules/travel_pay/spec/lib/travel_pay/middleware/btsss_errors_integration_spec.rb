# frozen_string_literal: true

require 'rails_helper'
require 'common/client/middleware/response/raise_custom_error'
require 'travel_pay/middleware/btsss_errors'

RSpec.describe TravelPay::Middleware::BtsssErrors, type: :integration do
  let(:btsss_400_body) do
    {
      'correlationId' => '95be195e-bdf1-4fa0-90d8-dc44381ffd10',
      'timeStamp' => '2025-09-15T22:32:38.77844Z',
      'statusCode' => 400,
      'message' => 'Validation failed: The claim does not have any expenses.',
      'success' => false,
      'data' => nil
    }.to_json
  end

  let(:btsss_500_body) do
    {
      'correlationId' => 'def-456',
      'statusCode' => 500,
      'message' => 'An internal error occurred.',
      'success' => false,
      'data' => nil
    }.to_json
  end

  let(:btsss_422_body) do
    {
      'correlationId' => 'ghi-789',
      'statusCode' => 422,
      'message' => 'Expense type is invalid for this claim.',
      'success' => false,
      'data' => nil
    }.to_json
  end

  let(:test_stubs) do
    Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('api/v2/claims/some-id/submit') do
        [400, { 'Content-Type' => 'application/json' }, btsss_400_body]
      end
      stub.get('api/v2/claims') do
        [500, { 'Content-Type' => 'application/json' }, btsss_500_body]
      end
      stub.post('api/v2/expenses/mileage') do
        [422, { 'Content-Type' => 'application/json' }, btsss_422_body]
      end
    end
  end

  context 'with btsss_errors middleware enabled (flag on)' do
    subject(:client) do
      stubs = test_stubs
      Faraday.new do |conn|
        conn.response :raise_custom_error, error_prefix: 'BTSSS-API'
        conn.response :btsss_errors
        conn.response :json
        conn.adapter :test, stubs
      end
    end

    it 'surfaces the BTSSS message in the detail for a 400' do
      expect { client.post('api/v2/claims/some-id/submit') }
        .to raise_error(Common::Exceptions::BackendServiceException) do |error|
          expect(error.message).to include('Validation failed: The claim does not have any expenses.')
          expect(error.original_body['detail']).to eq('Validation failed: The claim does not have any expenses.')
          expect(error.key).to eq('BTSSS-API_400')
        end
    end

    it 'surfaces the BTSSS message in the detail for a 500' do
      expect { client.get('api/v2/claims') }
        .to raise_error(Common::Exceptions::BackendServiceException) do |error|
          expect(error.message).to include('An internal error occurred.')
          expect(error.original_body['detail']).to eq('An internal error occurred.')
          expect(error.key).to eq('BTSSS-API_500')
        end
    end

    it 'surfaces the BTSSS message in the detail for a 422' do
      expect { client.post('api/v2/expenses/mileage') }
        .to raise_error(Common::Exceptions::BackendServiceException) do |error|
          expect(error.message).to include('Expense type is invalid for this claim.')
          expect(error.original_body['detail']).to eq('Expense type is invalid for this claim.')
          expect(error.key).to eq('BTSSS-API_422')
        end
    end
  end

  context 'without btsss_errors middleware (flag off / legacy behavior)' do
    subject(:client) do
      stubs = test_stubs
      Faraday.new do |conn|
        conn.response :raise_custom_error, error_prefix: 'BTSSS-API'
        conn.response :json
        conn.adapter :test, stubs
      end
    end

    it 'raises BackendServiceException with nil detail for a 400' do
      expect { client.post('api/v2/claims/some-id/submit') }
        .to raise_error(Common::Exceptions::BackendServiceException) do |error|
          expect(error.response_values[:detail]).to be_nil
          expect(error.message).not_to include('Validation failed')
        end
    end

    it 'raises BackendServiceException with nil detail for a 500' do
      expect { client.get('api/v2/claims') }
        .to raise_error(Common::Exceptions::BackendServiceException) do |error|
          expect(error.response_values[:detail]).to be_nil
          expect(error.message).not_to include('An internal error occurred')
        end
    end

    it 'raises BackendServiceException with nil detail for a 422' do
      expect { client.post('api/v2/expenses/mileage') }
        .to raise_error(Common::Exceptions::BackendServiceException) do |error|
          expect(error.response_values[:detail]).to be_nil
          expect(error.message).not_to include('Expense type is invalid')
        end
    end
  end
end
