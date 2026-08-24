# frozen_string_literal: true

require 'rails_helper'
require 'disability_compensation/service_connected'

RSpec.describe DisabilityCompensation::ServiceConnected do
  subject(:host) { Class.new { include DisabilityCompensation::ServiceConnected }.new }

  describe '#service_connected?' do
    it 'returns true for "Service Connected"' do
      expect(host.service_connected?('Service Connected')).to be true
    end

    it 'returns true for "1151 Granted"' do
      expect(host.service_connected?('1151 Granted')).to be true
    end

    it 'returns false for "Not Service Connected"' do
      expect(host.service_connected?('Not Service Connected')).to be false
    end

    it 'is case-insensitive' do
      expect(host.service_connected?('service connected')).to be true
      expect(host.service_connected?('SERVICE CONNECTED')).to be true
      expect(host.service_connected?('1151 GRANTED')).to be true
    end

    it 'returns false for nil' do
      expect(host.service_connected?(nil)).to be false
    end
  end
end
