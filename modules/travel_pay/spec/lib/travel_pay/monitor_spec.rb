# frozen_string_literal: true

require 'rails_helper'
require 'travel_pay/monitor'

RSpec.describe TravelPay::Monitor do
  subject(:monitor) { described_class.new }

  describe '#initialize' do
    it 'sets the service name to travel-pay' do
      expect(monitor.service).to eq('travel-pay')
    end
  end

  describe '#track_request' do
    it 'increments StatsD and logs the message' do
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info)

      monitor.track_request(:info, 'Test message', 'travel_pay.test.metric',
                            tags: ['result:success'])

      expect(StatsD).to have_received(:increment).with('travel_pay.test.metric',
                                                       tags: include('service:travel-pay',
                                                                     'result:success'))
    end
  end

  describe '#log' do
    it 'populates function, file, and line from the caller when call_location is not passed' do
      allow(Rails.logger).to receive(:info)

      monitor.log(:info, 'hello')

      expect(Rails.logger).to have_received(:info).with(
        'hello',
        hash_including(
          service: 'travel-pay',
          function: kind_of(String),
          file: kind_of(String),
          line: kind_of(Integer)
        )
      )
    end

    it 'filters context through the allowlist' do
      allow(Rails.logger).to receive(:warn)

      monitor.log(:warn, 'filtered', claim_id: 'C123', secret: 'nope')

      expect(Rails.logger).to have_received(:warn).with(
        'filtered',
        hash_including(context: hash_including(claim_id: 'C123', secret: '[FILTERED]'))
      )
    end
  end

  describe '#track_response_time' do
    it 'measures elapsed time via StatsD.measure and returns the block result' do
      allow(StatsD).to receive(:measure)

      result = monitor.track_response_time('claims', 'get_all') { 'response_data' }

      expect(result).to eq('response_data')
      expect(StatsD).to have_received(:measure).with(
        'travel_pay.claims.response_time',
        instance_of(Float),
        tags: ['travel_pay:get_all', 'status:success']
      )
    end

    it 'propagates exceptions from the block and still records the metric' do
      allow(StatsD).to receive(:measure)

      expect do
        monitor.track_response_time('claims', 'get_all') { raise Faraday::Error, 'timeout' }
      end.to raise_error(Faraday::Error, 'timeout')

      expect(StatsD).to have_received(:measure).with(
        'travel_pay.claims.response_time',
        instance_of(Float),
        tags: ['travel_pay:get_all', 'status:failure']
      )
    end
  end
end
