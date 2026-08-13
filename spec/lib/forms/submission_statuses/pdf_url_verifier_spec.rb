# frozen_string_literal: true

require 'rails_helper'
require 'forms/submission_statuses/pdf_url_verifier'

RSpec.describe Forms::SubmissionStatuses::PdfUrlVerifier do
  subject(:verifier) { described_class.new }

  let(:url) { 'https://a-bucket.s3.us-gov-west-1.amazonaws.com/some.pdf?X-Amz-Signature=abc' }

  describe '.connection' do
    it 'is memoized so it is not rebuilt per request' do
      expect(described_class.connection).to equal(described_class.connection)
    end

    it 'sets explicit open and read timeouts' do
      expect(described_class.connection.options.open_timeout).to eq(15)
      expect(described_class.connection.options.timeout).to eq(15)
    end

    it 'includes breakers middleware' do
      expect(described_class.connection.builder.handlers).to include(Breakers::UptimeMiddleware)
    end

    it 'passes the named service to breakers' do
      handler = described_class.connection.builder.handlers.find { |h| h == Breakers::UptimeMiddleware }
      expect(handler.instance_variable_get(:@kwargs)[:service_name])
        .to eq(described_class::BREAKERS_SERVICE_NAME)
    end
  end

  describe '.breakers_service' do
    it 'is named and matches on service_name' do
      service = described_class.breakers_service
      expect(service.name).to eq(described_class::BREAKERS_SERVICE_NAME)
      expect(service.handles_request?(request_env: nil, service_name: described_class::BREAKERS_SERVICE_NAME))
        .to be(true)
    end

    it 'does not match a different service name' do
      service = described_class.breakers_service
      expect(service.handles_request?(request_env: nil, service_name: 'SomethingElse')).to be(false)
    end
  end

  describe '#exists?' do
    it 'returns true when S3 responds 200' do
      stub_request(:get, url).to_return(status: 200)
      expect(verifier.exists?(url)).to be(true)
    end

    it 'returns false when S3 responds 404' do
      stub_request(:get, url).to_return(status: 404)
      expect(verifier.exists?(url)).to be(false)
    end

    it 'preserves the presigned query signature on the request' do
      stub = stub_request(:get, url).to_return(status: 200)
      verifier.exists?(url)
      expect(stub).to have_been_requested
    end

    it 'raises on timeout so breakers can record the failure' do
      stub_request(:get, url).to_timeout
      expect { verifier.exists?(url) }.to raise_error(Faraday::ConnectionFailed)
    end
  end
end
