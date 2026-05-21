# frozen_string_literal: true

require 'rails_helper'
require 'pagerduty/services_client'

describe PagerDuty::ServicesClient do
  subject { described_class.new }

  before(:all) do
    VCR.eject_cassette if VCR.current_cassette
    VCR.turn_off!
  end

  after(:all) do
    VCR.turn_on!
  end

  describe '#probe' do
    before do
      allow(Settings.maintenance).to receive(:services).and_return(
        { good: 'GOOD123', bad: 'BAD123', empty: nil }
      )
    end

    it 'returns the HTTP status for each configured service' do
      stub_request(:get, 'https://api.pagerduty.com/services/GOOD123')
        .to_return(status: 200,
                   headers: { 'Content-Type' => 'application/json; charset=utf-8' },
                   body: '{"service":{"id":"GOOD123"}}')
      stub_request(:get, 'https://api.pagerduty.com/services/BAD123')
        .to_return(status: 404)

      results = subject.probe

      expect(results).to contain_exactly(
        { setting_name: 'good', service_id: 'GOOD123', status: 200 },
        { setting_name: 'bad', service_id: 'BAD123', status: 404 },
        { setting_name: 'empty', service_id: nil, status: nil }
      )
    end

    it 'returns the upstream status for server errors' do
      stub_request(:get, 'https://api.pagerduty.com/services/GOOD123')
        .to_return(status: 200,
                   headers: { 'Content-Type' => 'application/json; charset=utf-8' },
                   body: '{"service":{"id":"GOOD123"}}')
      stub_request(:get, 'https://api.pagerduty.com/services/BAD123')
        .to_return(status: 500)

      results = subject.probe

      expect(results).to contain_exactly(
        { setting_name: 'good', service_id: 'GOOD123', status: 200 },
        { setting_name: 'bad', service_id: 'BAD123', status: 500 },
        { setting_name: 'empty', service_id: nil, status: nil }
      )
    end

    it 'returns nil status when the exception has no original_status' do
      stub_request(:get, 'https://api.pagerduty.com/services/GOOD123')
        .to_return(status: 200,
                   headers: { 'Content-Type' => 'application/json; charset=utf-8' },
                   body: '{"service":{"id":"GOOD123"}}')
      stub_request(:get, 'https://api.pagerduty.com/services/BAD123')
        .to_raise(Faraday::ConnectionFailed.new('boom'))

      results = subject.probe

      expect(results).to contain_exactly(
        { setting_name: 'good', service_id: 'GOOD123', status: 200 },
        { setting_name: 'bad', service_id: 'BAD123', status: nil },
        { setting_name: 'empty', service_id: nil, status: nil }
      )
    end
  end
end
