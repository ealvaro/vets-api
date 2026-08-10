# frozen_string_literal: true

require 'rails_helper'
require 'bep/monitor'

RSpec.describe BEP::Monitor do
  let(:metric_prefix) { 'api.test' }
  let(:service_name) { 'test-service' }

  let(:monitor) { described_class.new(service_name, metric_prefix:) }

  describe '#track_api_request' do
    let(:perform) do
      monitor.track_api_request(:get, 'foo-endpoint', additional_context: { priority: 5 }) do
        Faraday.get('http://www.example.com/foo/bar')
      end
    end

    context 'with a successful api call with 200 status' do
      before do
        stub_request(:get, 'http://www.example.com/foo/bar').to_return(status: 200, body: { success: true }.to_json)
      end

      it 'logs the correct message and metric' do
        expect(monitor).to receive(:track_request).with(:info,
                                                        'BEP::Monitor (test-service) GET foo-endpoint: 200 ',
                                                        'api.test.success',
                                                        call_location: Thread::Backtrace::Location,
                                                        method: :get,
                                                        endpoint_name: 'foo-endpoint',
                                                        service: 'test-service',
                                                        priority: 5).and_call_original
        perform
      end
    end

    context 'with a successful api call with 401 status' do
      before do
        stub_request(:get, 'http://www.example.com/foo/bar').to_return(status: 401,
                                                                       body: { error: 'auth failed' }.to_json)
      end

      it 'logs the correct message and metric' do
        expect(monitor).to receive(:track_request).with(:error,
                                                        'BEP::Monitor (test-service) GET foo-endpoint: 401 ',
                                                        'api.test.failure',
                                                        call_location: Thread::Backtrace::Location,
                                                        method: :get,
                                                        endpoint_name: 'foo-endpoint',
                                                        service: 'test-service',
                                                        priority: 5).and_call_original
        perform
      end
    end

    context 'with a failed api call' do
      before do
        stub_request(:get, 'http://www.example.com/foo/bar').to_raise(Faraday::TimeoutError.new('Request timed out'))
      end

      it 'logs the correct message and metric and re-raises the error' do
        expected_message = 'BEP::Monitor (test-service) GET foo-endpoint: API Error, Request timed out'
        expect(monitor).to receive(:track_request).with(:error,
                                                        expected_message,
                                                        'api.test.failure',
                                                        call_location: Thread::Backtrace::Location,
                                                        method: :get,
                                                        endpoint_name: 'foo-endpoint',
                                                        service: 'test-service',
                                                        priority: 5).and_call_original
        expect { perform }.to raise_error(Faraday::TimeoutError)
        # perform
      end
    end
  end
end
