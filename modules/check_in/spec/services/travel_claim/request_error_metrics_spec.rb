# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelClaim::RequestErrorMetrics do
  describe '.timeout_error?' do
    it 'returns true for GatewayTimeout' do
      expect(described_class.timeout_error?(Common::Exceptions::GatewayTimeout.new)).to be(true)
    end

    it 'returns true for Faraday::TimeoutError' do
      expect(described_class.timeout_error?(Faraday::TimeoutError.new)).to be(true)
    end

    it 'returns true for Timeout::Error' do
      expect(described_class.timeout_error?(Timeout::Error.new)).to be(true)
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

    it 'increments CIE request error metric with error_type and source tags' do
      described_class.increment(
        facility_type: 'cie',
        error_type: 'http',
        source: described_class::SOURCE_BTSSS
      )

      expect(StatsD).to have_received(:increment).with(
        CheckIn::Constants::CIE_STATSD_BTSSS_V1_REQUEST_ERROR,
        tags: ['error_type:http', 'source:btsss']
      )
    end

    it 'increments empty_response metric with source and step tags' do
      described_class.increment(
        facility_type: 'cie',
        error_type: 'empty_response',
        source: described_class::SOURCE_BTSSS,
        step: described_class::STEP_FIND_OR_ADD_APPOINTMENT
      )

      expect(StatsD).to have_received(:increment).with(
        CheckIn::Constants::CIE_STATSD_BTSSS_V1_REQUEST_ERROR,
        tags: ['error_type:empty_response', 'source:btsss', 'step:find_or_add_appointment']
      )
    end

    it 'increments OH auth timeout metric with source auth tag' do
      described_class.increment(
        facility_type: 'oh',
        error_type: 'timeout',
        source: described_class::SOURCE_AUTH
      )

      expect(StatsD).to have_received(:increment).with(
        CheckIn::Constants::OH_STATSD_BTSSS_V1_REQUEST_ERROR,
        tags: ['error_type:timeout', 'source:auth']
      )
    end
  end
end
