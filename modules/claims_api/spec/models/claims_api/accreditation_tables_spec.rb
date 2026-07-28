# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::AccreditationTables do
  describe '.representative' do
    it 'routes to the veteran service representative model by default' do
      expect(described_class.representative).to eq(Veteran::Service::Representative)
    end
  end

  describe '.organization' do
    it 'routes to the veteran service organization model by default' do
      expect(described_class.organization).to eq(Veteran::Service::Organization)
    end
  end

  describe '.use_claims_accreditation_tables?' do
    it 'returns false when the feature flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(described_class::FLAG).and_return(false)

      expect(described_class.use_claims_accreditation_tables?).to be(false)
    end

    it 'returns true when the feature flag is enabled' do
      allow(Flipper).to receive(:enabled?).with(described_class::FLAG).and_return(true)

      expect(described_class.use_claims_accreditation_tables?).to be(true)
    end
  end
end
