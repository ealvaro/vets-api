# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelClaim::RequestErrorMetrics do
  describe '.timeout_error?' do
    it 'returns true for GatewayTimeout' do
      expect(described_class.timeout_error?(Common::Exceptions::GatewayTimeout.new)).to be(true)
    end

    it 'returns true for BackendServiceException with status 408' do
      error = Common::Exceptions::BackendServiceException.new('TEST', {}, 408)
      expect(described_class.timeout_error?(error)).to be(true)
    end

    it 'returns true for BackendServiceException with status 504' do
      error = Common::Exceptions::BackendServiceException.new('TEST', {}, 504)
      expect(described_class.timeout_error?(error)).to be(true)
    end

    it 'returns false for other HTTP errors' do
      error = Common::Exceptions::BackendServiceException.new('TEST', {}, 500)
      expect(described_class.timeout_error?(error)).to be(false)
    end
  end

  describe '.increment' do
    before { allow(StatsD).to receive(:increment) }

    it 'increments CIE request error metric with error_type tag' do
      described_class.increment(facility_type: 'cie', error_type: 'http')

      expect(StatsD).to have_received(:increment).with(
        CheckIn::Constants::CIE_STATSD_BTSSS_V1_REQUEST_ERROR,
        tags: ['error_type:http']
      )
    end

    it 'increments OH request error metric with error_type tag' do
      described_class.increment(facility_type: 'oh', error_type: 'timeout')

      expect(StatsD).to have_received(:increment).with(
        CheckIn::Constants::OH_STATSD_BTSSS_V1_REQUEST_ERROR,
        tags: ['error_type:timeout']
      )
    end
  end
end
