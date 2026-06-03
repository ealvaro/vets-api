# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/service_exception'

RSpec.describe Lighthouse::ServiceException do
  describe '.missing_http_status_server_error' do
    context 'when error is a Faraday::TimeoutError' do
      let(:error) { Faraday::TimeoutError.new('execution expired') }

      it 'returns a GatewayTimeout exception (504)' do
        result = described_class.missing_http_status_server_error(error)
        expect(result).to be_a(Common::Exceptions::GatewayTimeout)
      end
    end

    context 'when error is not a Faraday::TimeoutError' do
      let(:error) { StandardError.new('something went wrong') }

      it 'returns a ServiceError with error details' do
        result = described_class.missing_http_status_server_error(error)
        expect(result).to be_a(Common::Exceptions::ServiceError)
      end
    end
  end

  describe '.send_error' do
    let(:service_name) { 'test_service' }
    let(:client_id) { 'test_client_id' }
    let(:url) { 'https://api.va.gov/test' }

    before do
      allow(described_class).to receive(:send_error_logs)
    end

    context 'when error is a Faraday::TimeoutError (no response)' do
      let(:error) { Faraday::TimeoutError.new('execution expired') }

      it 'raises Common::Exceptions::GatewayTimeout' do
        expect { described_class.send_error(error, service_name, client_id, url) }
          .to raise_error(Common::Exceptions::GatewayTimeout)
      end
    end

    context 'when error does not respond to :response' do
      let(:error) { StandardError.new('some error') }

      it 'returns the error without raising' do
        result = described_class.send_error(error, service_name, client_id, url)
        expect(result).to eq(error)
      end
    end

    context 'when error has a response with a mapped status code' do
      let(:error) do
        Faraday::ClientError.new('not found', { status: 404, body: { 'errors' => [] } })
      end

      it 'raises the mapped exception class' do
        expect { described_class.send_error(error, service_name, client_id, url) }
          .to raise_error(Common::Exceptions::ResourceNotFound)
      end
    end
  end

  describe '.error_class' do
    it 'returns the mapped exception for a known status code' do
      expect(described_class.error_class(504)).to eq(Common::Exceptions::GatewayTimeout)
    end

    it 'returns ServiceError for unmapped status codes' do
      expect(described_class.error_class(418)).to eq(Common::Exceptions::ServiceError)
    end
  end
end
