# frozen_string_literal: true

require 'rails_helper'
require 'benefits_claims/providers/lighthouse/builders/claim_status_meta_builder'

RSpec.describe BenefitsClaims::Providers::Lighthouse::Builders::ClaimStatusMetaBuilder do
  before do
    Rails.cache.delete(described_class::CACHE_KEY)
  end

  describe '.build' do
    it 'loads metadata once and returns deep copies on each call' do
      cached = nil
      allow(Rails.cache).to receive(:fetch).with(described_class::CACHE_KEY).twice do |_key, &block|
        cached ||= block.call
      end

      allow(BenefitsClaims::ClaimStatusMeta::ConfigLoader).to receive(:load)
        .with(provider: :lighthouse)
        .once
        .and_return({ 'header' => { 'title' => 'Original' } })

      first = described_class.build
      first['header']['title'] = 'Mutated'
      second = described_class.build

      expect(second).to eq('header' => { 'title' => 'Original' })
    end

    it 'logs and returns empty hash when config loading fails' do
      error = ArgumentError.new('bad file')
      allow(BenefitsClaims::ClaimStatusMeta::ConfigLoader).to receive(:load)
        .with(provider: :lighthouse)
        .and_raise(error)

      expect(Rails.logger).to receive(:error).with(
        '[BenefitsClaims::Providers::Lighthouse::Builders::ClaimStatusMetaBuilder] Failed to load metadata config',
        { message: error.message }
      )

      expect(described_class.build).to eq({})
    end
  end
end
