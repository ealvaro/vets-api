# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coe::ServiceBranch do
  describe '.data' do
    it 'returns the parsed service branch table' do
      expect(described_class.data).to be_a(Hash)
      expect(described_class.data['ARMY']).to include('label' => 'Army', 'group' => 'Army')
    end
  end

  describe '.keys' do
    it 'returns frozen branch keys' do
      expect(described_class.keys).to eq(described_class.data.keys)
      expect(described_class.keys).to be_frozen
    end
  end

  describe '.lgy_military_branch_and_service_type' do
    it 'returns nil pair for an unknown branch key' do
      expect(described_class.lgy_military_branch_and_service_type('NOT_A_REAL_BRANCH')).to eq([nil, nil])
    end

    it 'maps active Army to ARMY and ACTIVE_DUTY' do
      expect(described_class.lgy_military_branch_and_service_type('ARMY')).to eq(%w[ARMY ACTIVE_DUTY])
    end

    it 'maps Army Reserve to ARMY and RESERVE_NATIONAL_GUARD' do
      expect(described_class.lgy_military_branch_and_service_type('AR')).to eq(%w[ARMY RESERVE_NATIONAL_GUARD])
    end

    it 'maps Army National Guard to ARMY and RESERVE_NATIONAL_GUARD' do
      expect(described_class.lgy_military_branch_and_service_type('ARNG')).to eq(%w[ARMY RESERVE_NATIONAL_GUARD])
    end

    it 'maps Space Force to AIR_FORCE and ACTIVE_DUTY' do
      expect(described_class.lgy_military_branch_and_service_type('SF')).to eq(%w[AIR_FORCE ACTIVE_DUTY])
    end

    it 'maps an unknown group in the table to LGY military branch OTHER' do
      stub_const(
        'Coe::ServiceBranch::TABLE',
        { 'ZZZ' => { 'label' => 'Test', 'group' => 'Unknown Group' } }.freeze
      )

      expect(described_class.lgy_military_branch_and_service_type('ZZZ')).to eq(%w[OTHER ACTIVE_DUTY])
    end
  end
end
