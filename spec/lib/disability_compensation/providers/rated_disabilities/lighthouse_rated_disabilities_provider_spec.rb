# frozen_string_literal: true

require 'rails_helper'
require 'disability_compensation/factories/api_provider_factory'
require 'disability_compensation/providers/rated_disabilities/lighthouse_rated_disabilities_provider'
require 'support/disability_compensation_form/shared_examples/rated_disabilities_provider'
require 'lighthouse/service_exception'

RSpec.describe LighthouseRatedDisabilitiesProvider do
  let(:current_user) { build(:user, :loa3) }

  before(:all) do
    @provider = LighthouseRatedDisabilitiesProvider.new('123498767V234859')
  end

  before do
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('blahblech')
    allow(StatsD).to receive(:increment)
  end

  it_behaves_like 'rated disabilities provider'

  it 'retrieves rated disabilities from the Lighthouse API' do
    VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
      response = @provider.get_rated_disabilities('', '')
      expect(response.rated_disabilities.length).to eq(1)
    end
  end

  describe 'caching' do
    before do
      @provider = LighthouseRatedDisabilitiesProvider.new('123498767V234859')
      allow(Flipper).to receive(:enabled?).with(:disability_compensation_rated_disabilities_cache).and_return(true)
      @memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(@memory_cache)
    end

    it 'caches the raw API response and does not call the API on subsequent get_rated_disabilities requests' do
      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        first_response = @provider.get_rated_disabilities('', '')
        expect(first_response.rated_disabilities.length).to eq(1)
      end

      # Second call should come from cache, not VCR (which would raise if replayed)
      second_response = @provider.get_rated_disabilities('', '')
      expect(second_response.rated_disabilities.length).to eq(1)
    end

    it 'caches the raw API response and does not call the API on subsequent get_combined_disability_rating requests' do
      first_response = nil
      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        first_response = @provider.get_combined_disability_rating('', '')
        expect(first_response).to be_present
      end

      # Second call should come from cache, not VCR (which would raise if replayed)
      second_response = @provider.get_combined_disability_rating('', '')
      expect(second_response).to eq(first_response)
    end

    it 'shares the cache between get_rated_disabilities and get_combined_disability_rating' do
      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        @provider.get_rated_disabilities('', '')
      end

      # get_combined_disability_rating should use the same cached raw response
      rating = @provider.get_combined_disability_rating('', '')
      expect(rating).to be_present
    end

    it 'uses a hashed per-ICN cache key' do
      expected_key = "lighthouse_rated_disabilities/v2/#{Digest::SHA256.hexdigest('123498767V234859')}"

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        @provider.get_rated_disabilities('', '')
      end

      expect(Rails.cache.exist?(expected_key)).to be true
    end

    it 'does not read stale v1 cache entries written by the old code' do
      old_key = "lighthouse_rated_disabilities/#{Digest::SHA256.hexdigest('123498767V234859')}"
      stale_response = instance_double(DisabilityCompensation::ApiProvider::RatedDisabilitiesResponse)
      @memory_cache.write(old_key, stale_response)

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        response = @provider.get_rated_disabilities('', '')
        expect(response).to be_a(DisabilityCompensation::ApiProvider::RatedDisabilitiesResponse)
        expect(response).not_to equal(stale_response)
      end
    end

    it 'increments StatsD on cache hit' do
      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        @provider.get_rated_disabilities('', '')
      end

      expect(StatsD).to receive(:increment).with('api.lighthouse_rated_disabilities.cache.hit')
      @provider.get_rated_disabilities('', '')
    end

    it 'increments StatsD on cache miss' do
      expect(StatsD).to receive(:increment).with('api.lighthouse_rated_disabilities.cache.miss')

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        @provider.get_rated_disabilities('', '')
      end
    end

    it 'falls back to API when cache read fails' do
      allow(Rails.cache).to receive(:read).and_raise(Redis::ConnectionError.new('Connection refused'))
      allow(Rails.logger).to receive(:error)

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        response = @provider.get_rated_disabilities('', '')
        expect(response.rated_disabilities.length).to eq(1)
      end

      expect(Rails.logger).to have_received(:error).with(/Rated disabilities cache read failed/)
    end

    it 'logs and continues when cache write fails' do
      allow(Rails.cache).to receive(:read).and_return(nil)
      allow(Rails.cache).to receive(:write).and_raise(Redis::ConnectionError.new('Connection refused'))
      allow(Rails.logger).to receive(:error)

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        response = @provider.get_rated_disabilities('', '')
        expect(response.rated_disabilities.length).to eq(1)
      end

      expect(Rails.logger).to have_received(:error).with(/Rated disabilities cache write failed/)
    end

    it 'stores encrypted ciphertext in the cache, not the raw response' do
      cache_key = "lighthouse_rated_disabilities/v2/#{Digest::SHA256.hexdigest('123498767V234859')}"

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        @provider.get_rated_disabilities('', '')
      end

      raw = @memory_cache.read(cache_key)
      expect(raw).to be_a(String)
      expect(raw).not_to include('diagnostic_text')
      expect(raw).not_to include('individual_ratings')
    end

    it 'falls back to the API and does not raise when cached data cannot be decrypted' do
      cache_key = "lighthouse_rated_disabilities/v2/#{Digest::SHA256.hexdigest('123498767V234859')}"
      @memory_cache.write(cache_key, 'this-is-not-valid-ciphertext')
      allow(Rails.logger).to receive(:error)

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        response = @provider.get_rated_disabilities('', '')
        expect(response.rated_disabilities.length).to eq(1)
      end

      expect(Rails.logger).to have_received(:error).with(/Rated disabilities cache read failed/)
    end

    it 'falls back to the API and does not raise when decrypted data is not valid JSON' do
      cache_key = "lighthouse_rated_disabilities/v2/#{Digest::SHA256.hexdigest('123498767V234859')}"
      allow(Rails.logger).to receive(:error)

      lockbox = Lockbox.new(key: Settings.lockbox.master_key, encode: true)
      @memory_cache.write(cache_key, lockbox.encrypt('not-json'))

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        response = @provider.get_rated_disabilities('', '')
        expect(response.rated_disabilities.length).to eq(1)
      end

      expect(Rails.logger).to have_received(:error).with(/Rated disabilities cache read failed/)
    end
  end

  describe 'when cache feature flag is disabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:disability_compensation_rated_disabilities_cache).and_return(false)
      @memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(@memory_cache)
    end

    it 'does not cache and calls the API every time' do
      cache_key = "lighthouse_rated_disabilities/v2/#{Digest::SHA256.hexdigest('123498767V234859')}"

      VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
        response = @provider.get_rated_disabilities('', '')
        expect(response.rated_disabilities.length).to eq(1)
      end

      expect(Rails.cache.exist?(cache_key)).to be false
    end
  end

  it 'returns an empty list when individual_ratings is nil' do
    allow_any_instance_of(VeteranVerification::Service).to receive(:get_rated_disabilities).and_return(
      { 'data' => { 'attributes' => { 'individual_ratings' => nil } } }
    )
    response = @provider.get_rated_disabilities('', '')
    expect(response.rated_disabilities).to eq([])
  end

  it 'returns the proper error through the GatewayTimeout class' do
    allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(Faraday::TimeoutError)
    expect do
      @provider.get_rated_disabilities('', '')
    end.to raise_error(Common::Exceptions::GatewayTimeout)
  end

  it 'returns the proper error through the ServiceError class' do
    allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(Faraday::ServerError.new(status: nil))
    expect do
      @provider.get_rated_disabilities('', '')
    end.to raise_error(Common::Exceptions::ServiceError)
  end

  Lighthouse::ServiceException::ERROR_MAP.except(422, 499, 501).each do |status, error_class|
    it "throws a #{status} error if Lighthouse sends it back" do
      expect do
        test_error(
          "lighthouse/veteran_verification/disability_rating/#{status == 404 ? '404_ICN' : status}_response"
        )
      end.to raise_error error_class
    end

    def test_error(cassette_path)
      VCR.use_cassette(cassette_path) do
        @provider.get_rated_disabilities('', '')
      end
    end
  end
end
