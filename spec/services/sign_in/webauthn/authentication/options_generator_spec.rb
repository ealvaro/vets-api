# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::Webauthn::Authentication::OptionsGenerator do
  describe '#perform' do
    subject { described_class.new.perform }

    let(:challenge_id) { 'some-challenge-id' }
    let(:cache_key) { "#{described_class::CACHE_KEY_PREFIX}:#{challenge_id}" }
    let(:rp_id) { WebAuthn.configuration.rp_id }
    let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      allow(SecureRandom).to receive(:uuid).and_return(challenge_id)
    end

    it 'returns the challenge id and caches the challenge under its cache key' do
      options, returned_challenge_id = subject
      expect(returned_challenge_id).to eq(challenge_id)
      expect(Rails.cache.read(cache_key)).to eq(options.challenge)
    end

    it 'requests discoverable options requiring user verification for the configured rp' do
      expect(WebAuthn::Credential).to receive(:options_for_get)
        .with(user_verification: 'required', rp_id:)
        .and_call_original

      subject
    end
  end
end
