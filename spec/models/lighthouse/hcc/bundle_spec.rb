# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::HCC::Bundle do
  describe '#initialize' do
    context 'with valid data' do
      subject do
        described_class.new(bundle_hash, entries)
      end

      let(:bundle_hash) do
        JSON.parse(
          Rails.root.join('spec', 'fixtures', 'lighthouse', 'hcc', 'bundle.json').read
        )
      end

      let(:entries) do
        bundle_hash['entry'].map do |entry|
          Lighthouse::HCC::Invoice.new(entry)
        end
      end

      it 'calculates last_updated_on from entries that have meta.lastUpdated' do
        expect(subject.meta[:copay_summary][:last_updated_on])
          .to eq(Time.iso8601('2025-08-29T00:00:00Z'))
      end
    end
  end
end
