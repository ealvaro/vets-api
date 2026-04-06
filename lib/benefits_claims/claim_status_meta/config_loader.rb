# frozen_string_literal: true

require 'json'

module BenefitsClaims
  module ClaimStatusMeta
    class ConfigLoader
      BASE_PATH = Rails.root.join('config', 'benefits_claims', 'claim_status_meta')

      class << self
        def load(provider:, variant: 'default')
          provider_name = provider.to_s
          variant_name = variant.to_s
          config = if Rails.env.development? || Rails.env.test?
                     parse_config(provider_name, variant_name)
                   else
                     cached_config(provider_name, variant_name)
                   end

          # Callers may mutate values (for dynamic fields); always return a copy.
          config.deep_dup
        end

        private

        def cached_config(provider_name, variant_name)
          Rails.cache.fetch("benefits_claims/claim_status_meta/#{provider_name}/#{variant_name}") do
            parse_config(provider_name, variant_name).freeze
          end
        end

        def parse_config(provider_name, variant_name)
          file_path = BASE_PATH.join(provider_name, "#{variant_name}.json")
          raise ArgumentError, "Claim status metadata file not found: #{file_path}" unless File.exist?(file_path)

          parsed = JSON.parse(File.read(file_path))
          raise ArgumentError, "Claim status metadata must be a JSON object: #{file_path}" unless parsed.is_a?(Hash)

          parsed
        rescue JSON::ParserError => e
          raise ArgumentError, "Invalid JSON in claim status metadata file #{file_path}: #{e.message}"
        end
      end
    end
  end
end
