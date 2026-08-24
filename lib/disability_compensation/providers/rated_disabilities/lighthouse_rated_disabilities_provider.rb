# frozen_string_literal: true

require 'disability_compensation/providers/rated_disabilities/rated_disabilities_provider'
require 'disability_compensation/responses/rated_disabilities_response'
require 'disability_compensation/service_connected'
require 'lighthouse/veteran_verification/service'

class LighthouseRatedDisabilitiesProvider
  include RatedDisabilitiesProvider
  include DisabilityCompensation::ServiceConnected

  # @param [string] :icn icn of the user
  def initialize(icn)
    @service = VeteranVerification::Service.new
    @icn = icn
  end

  # @param [string] lighthouse_client_id: the lighthouse_client_id requested from Lighthouse
  # @param [string] lighthouse_rsa_key_path: path to the private RSA key used to create the lighthouse_client_id
  # @return [integer] the combined disability rating
  def get_combined_disability_rating(lighthouse_client_id = nil, lighthouse_rsa_key_path = nil)
    data = get_data(lighthouse_client_id, lighthouse_rsa_key_path)
    data.dig('data', 'attributes', 'combined_disability_rating')
  end

  RATED_DISABILITIES_CACHE_TTL = 60.minutes

  # @param [string] lighthouse_client_id: the lighthouse_client_id requested from Lighthouse
  # @param [string] lighthouse_rsa_key_path: path to the private RSA key used to create the lighthouse_client_id
  # @return [DisabilityCompensation::ApiProvider::RatedDisabilitiesResponse] a list of individual disability ratings
  # @option options [string] :invoker where this method was called from
  def get_rated_disabilities(lighthouse_client_id = nil, lighthouse_rsa_key_path = nil, options = {})
    data = get_data(lighthouse_client_id, lighthouse_rsa_key_path, options)
    transform(data.dig('data', 'attributes', 'individual_ratings') || [])
  end

  # @param [string] lighthouse_client_id: the lighthouse_client_id requested from Lighthouse
  # @param [string] lighthouse_rsa_key_path: path to the private RSA key used to create the lighthouse_client_id
  # @option options [string] :invoker where this method was called from
  # @return [Hash] the raw Lighthouse API response hash containing 'data' => 'attributes' =>
  #   'combined_disability_rating' and 'individual_ratings'
  def get_data(lighthouse_client_id = nil, lighthouse_rsa_key_path = nil, options = {})
    if Flipper.enabled?(:disability_compensation_rated_disabilities_cache)
      fetch_data_with_cache(lighthouse_client_id, lighthouse_rsa_key_path, options)
    else
      @service.get_rated_disabilities(@icn, lighthouse_client_id, lighthouse_rsa_key_path, options)
    end
  end

  def transform(data)
    rated_disabilities =
      data.map do |rated_disability|
        DisabilityCompensation::ApiProvider::RatedDisability.new(
          name: rated_disability['diagnostic_text'],
          decision_code: decision_code_transform(rated_disability['decision']),
          decision_text: rated_disability['decision'],
          diagnostic_code: rated_disability['diagnostic_type_code'].to_i,
          hyphenated_diagnostic_code: rated_disability['hyph_diagnostic_type_code'].presence&.to_i,
          effective_date: rated_disability['effective_date'],
          rated_disability_id: rated_disability['disability_rating_id'],
          rating_decision_id: 0,
          rating_percentage: if service_connected?(rated_disability['decision'])
                               rated_disability['rating_percentage']
                             end,
          # TODO: figure out if this is important
          related_disability_date: DateTime.now
        )
      end
    DisabilityCompensation::ApiProvider::RatedDisabilitiesResponse.new(rated_disabilities:)
  end

  def decision_code_transform(decision_code_text)
    service_connected?(decision_code_text) ? 'SVCCONNCTED' : 'NOTSVCCON'
  end

  private

  def fetch_data_with_cache(lighthouse_client_id, lighthouse_rsa_key_path, options)
    cache_key = "lighthouse_rated_disabilities/v2/#{Digest::SHA256.hexdigest(@icn)}"

    begin
      cached = Rails.cache.read(cache_key)
      result = cached ? decrypt_data(cached) : nil
    rescue => e
      Rails.logger.error("Rated disabilities cache read failed: #{e.message}")
      result = nil
    end

    if result
      StatsD.increment('api.lighthouse_rated_disabilities.cache.hit')
    else
      StatsD.increment('api.lighthouse_rated_disabilities.cache.miss')
      result = @service.get_rated_disabilities(@icn, lighthouse_client_id, lighthouse_rsa_key_path, options)

      begin
        Rails.cache.write(cache_key, encrypt_data(result), expires_in: RATED_DISABILITIES_CACHE_TTL)
      rescue => e
        Rails.logger.error("Rated disabilities cache write failed: #{e.message}")
      end
    end

    result
  end

  def lockbox
    @lockbox ||= Lockbox.new(key: Settings.lockbox.master_key, encode: true)
  end

  def encrypt_data(data)
    lockbox.encrypt(data.to_json)
  end

  def decrypt_data(encrypted_data)
    JSON.parse(lockbox.decrypt(encrypted_data))
  end
end
