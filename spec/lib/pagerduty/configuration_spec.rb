# frozen_string_literal: true

require 'rails_helper'
require 'pagerduty/configuration'

describe PagerDuty::Configuration do
  describe '.service_ids' do
    it 'returns every configured service id' do
      allow(Settings.maintenance).to receive(:services).and_return(
        { appeals: 'P9S4RFU', evss: 'PZKWB6Y' }
      )

      expect(described_class.service_ids).to eq(%w[P9S4RFU PZKWB6Y])
    end

    it 'drops services that have no configured id' do
      allow(Settings.maintenance).to receive(:services).and_return(
        { appeals: 'P9S4RFU', vaos: nil, evss: 'PZKWB6Y', travel_pay: nil }
      )

      expect(described_class.service_ids).to eq(%w[P9S4RFU PZKWB6Y])
    end

    it 'returns an empty array when every service is unconfigured' do
      allow(Settings.maintenance).to receive(:services).and_return({ vaos: nil, travel_pay: nil })

      expect(described_class.service_ids).to eq([])
    end

    it 'returns an empty array when no services are configured at all' do
      allow(Settings.maintenance).to receive(:services).and_return(nil)

      expect(described_class.service_ids).to eq([])
    end
  end

  describe '.service_map' do
    it 'maps service ids back to their service names' do
      allow(Settings.maintenance).to receive(:services).and_return(
        { appeals: 'P9S4RFU', evss: 'PZKWB6Y' }
      )

      expect(described_class.service_map).to eq('P9S4RFU' => :appeals, 'PZKWB6Y' => :evss)
    end

    it 'returns an empty hash when no services are configured at all' do
      allow(Settings.maintenance).to receive(:services).and_return(nil)

      expect(described_class.service_map).to eq({})
    end
  end
end
