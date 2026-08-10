# frozen_string_literal: true

require 'rails_helper'
require 'bep/service'

class TestConfiguration < BEP::Configuration
  def base_path
    'http://www.example.com'
  end

  def service_name
    'test-service'
  end
end

class TestService < BEP::Service
  configuration TestConfiguration
end

RSpec.describe BEP::Service do
  let(:service) { TestService.new }

  describe '#perform_with_monitoring' do
    before do
      stub_request(:get, 'http://www.example.com/foo/bar').to_return(status: 200, body: { success: true }.to_json)
    end

    it 'creates a new monitor and uses it to track the request' do
      monitor = service.send(:monitor)
      expect(monitor).to be_a(BEP::Monitor)
      expect(monitor.service).to eq('bep-generic-api')
      expect(monitor).to receive(:track_api_request).with(:get, 'foo', additional_context: {}, call_location: Thread::Backtrace::Location).and_call_original
      service.perform_with_monitoring(method: :get, path: '/foo/bar')
    end

    it 'calls the super class perform method' do
      expect(service).to receive(:perform).with(:get, '/foo/bar', nil, nil, nil).and_call_original
      response = service.perform_with_monitoring(method: :get, path: '/foo/bar')
      expect(response.status).to eq(200)
      expect(JSON.parse(response.body)).to eq({ 'success' => true })
    end
  end
end
