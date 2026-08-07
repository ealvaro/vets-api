# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::FacilityAccount do
  describe '.sum_balances' do
    def account(current_balance)
      described_class.new(station_id: '896', current_balance:)
    end

    it 'totals the current balance across accounts' do
      expect(described_class.sum_balances([account(105.24), account(15.0)])).to eq(120.24)
    end

    it 'reports zero for no accounts' do
      expect(described_class.sum_balances([])).to eq(0.0)
    end

    it 'sums in decimal so repeating fractions do not drift' do
      expect(described_class.sum_balances([account(0.1), account(0.2)])).to eq(0.3)
    end

    it 'treats an unset balance as zero' do
      expect(described_class.sum_balances([account(nil), account(15.0)])).to eq(15.0)
    end

    it 'nets credits against charges' do
      expect(described_class.sum_balances([account(50.0), account(-10.0)])).to eq(40.0)
    end
  end
end
