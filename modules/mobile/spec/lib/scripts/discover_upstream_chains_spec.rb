# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../lib/scripts/discover_upstream_chains'

RSpec.describe DiscoverUpstreamChains do
  let(:discover_upstream_chains) { described_class.new }

  describe '#discover_all_chains' do
    it 'excludes files inside a concerns/ directory' do
      allow(Dir).to receive(:glob).and_return(
        ['app/controllers/mobile/v0/concerns/id_validation.rb']
      )
      expect(discover_upstream_chains).not_to receive(:build_chain_entry)

      result = discover_upstream_chains.send(:discover_all_chains)

      expect(result).to eq([])
    end

    it 'includes controller files whose name contains "concerns"' do
      allow(Dir).to receive(:glob).and_return(
        ['app/controllers/mobile/v0/concerns_controller.rb']
      )
      chain_entry_stub = { endpoint: 'app/controllers/mobile/v0/concerns_controller.rb', feature: 'Concerns',
                           chains: [] }
      allow(discover_upstream_chains).to receive(:build_chain_entry).and_return(chain_entry_stub)

      result = discover_upstream_chains.send(:discover_all_chains)

      expect(result).to eq([chain_entry_stub])
    end
  end

  describe '#feature_name_from_path' do
    it 'converts a single-word controller path to a capitalized feature name' do
      result = discover_upstream_chains.send(
        :feature_name_from_path, 'app/controllers/mobile/v0/appointments_controller.rb'
      )

      expect(result).to eq('Appointments')
    end

    it 'converts a multi-word controller path to a capitalized feature name' do
      result = discover_upstream_chains.send(
        :feature_name_from_path, 'app/controllers/mobile/v0/disability_rating_controller.rb'
      )

      expect(result).to eq('Disability Rating')
    end
  end

  describe '#classify_upstream' do
    it 'returns the upstream group for a known constant' do
      result = discover_upstream_chains.send(:classify_upstream, 'VAOS::V2::SystemsService')

      expect(result).to eq('VAOS')
    end

    it 'returns nil for an unknown constant' do
      result = discover_upstream_chains.send(:classify_upstream, 'Foos::BarService')

      expect(result).to be_nil
    end
  end
end
