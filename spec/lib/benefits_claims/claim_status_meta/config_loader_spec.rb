# frozen_string_literal: true

require 'rails_helper'
require 'benefits_claims/claim_status_meta/config_loader'

RSpec.describe BenefitsClaims::ClaimStatusMeta::ConfigLoader do
  let(:base_path) { described_class::BASE_PATH }
  let(:test_provider) { "rspec_#{SecureRandom.hex(6)}" }

  after do
    FileUtils.rm_rf(base_path.join(test_provider))
  end

  describe '.load' do
    it 'loads metadata and returns a deep copy' do
      write_raw_json(provider: test_provider, variant: 'default', content: { 'outer' => { 'value' => 'one' } }.to_json)

      first = described_class.load(provider: test_provider)
      first['outer']['value'] = 'mutated'
      second = described_class.load(provider: test_provider)

      expect(second).to eq('outer' => { 'value' => 'one' })
    end

    it 'supports symbol variants' do
      write_raw_json(provider: test_provider, variant: 'custom_variant', content: { 'flag' => true }.to_json)

      expect(described_class.load(provider: test_provider.to_sym, variant: :custom_variant)).to eq('flag' => true)
    end

    it 'raises when file does not exist' do
      expect { described_class.load(provider: :missing) }
        .to raise_error(ArgumentError, %r{Claim status metadata file not found: .*/missing/default\.json})
    end

    it 'raises when metadata is not a JSON object' do
      write_raw_json(provider: test_provider, variant: 'array_value', content: '[]')

      expect { described_class.load(provider: test_provider, variant: :array_value) }
        .to raise_error(
          ArgumentError,
          %r{Claim status metadata must be a JSON object: .*/#{test_provider}/array_value\.json}
        )
    end

    it 'raises when JSON is invalid' do
      write_raw_json(provider: test_provider, variant: 'invalid', content: '{"foo":')

      expect { described_class.load(provider: test_provider, variant: :invalid) }
        .to raise_error(ArgumentError, /Invalid JSON in claim status metadata file/)
    end

    it 'uses cache outside development/test and still returns deep copies' do
      write_raw_json(provider: test_provider, variant: 'default', content: { 'a' => { 'b' => 1 } }.to_json)
      allow(Rails.env).to receive_messages(development?: false, test?: false)

      cached_value = nil
      expect(Rails.cache).to receive(:fetch)
        .with("benefits_claims/claim_status_meta/#{test_provider}/default").twice do |_key, &block|
          cached_value ||= block.call
        end

      first = described_class.load(provider: test_provider)
      first['a']['b'] = 99
      second = described_class.load(provider: test_provider)

      expect(second).to eq('a' => { 'b' => 1 })
    end
  end

  def write_raw_json(provider:, variant:, content:)
    provider_dir = base_path.join(provider)
    FileUtils.mkdir_p(provider_dir)
    File.write(provider_dir.join("#{variant}.json"), content)
  end
end
