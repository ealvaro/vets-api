# frozen_string_literal: true

require 'benefits_claims/claim_status_meta/config_loader'

module BenefitsClaims
  module Providers
    module Lighthouse
      module Builders
        class ClaimStatusMetaBuilder
          CACHE_KEY = 'benefits_claims/providers/lighthouse/claim_status_meta'

          class << self
            def build
              cached_metadata.deep_dup
            rescue ArgumentError => e
              Rails.logger.error(
                '[BenefitsClaims::Providers::Lighthouse::Builders::ClaimStatusMetaBuilder] ' \
                'Failed to load metadata config',
                { message: e.message }
              )
              {}
            end

            private

            def cached_metadata
              Rails.cache.fetch(CACHE_KEY) do
                BenefitsClaims::ClaimStatusMeta::ConfigLoader.load(provider: :lighthouse).freeze
              end
            end
          end
        end
      end
    end
  end
end
