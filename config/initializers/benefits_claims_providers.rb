# frozen_string_literal: true

require 'benefits_claims/providers/provider_registry'
require 'benefits_claims/providers/lighthouse/lighthouse_benefits_claims_provider'

BenefitsClaims::Providers::ProviderRegistry.register(
  :lighthouse,
  BenefitsClaims::Providers::Lighthouse::LighthouseBenefitsClaimsProvider,
  feature_flag: 'benefits_claims_lighthouse_provider',
  platform_flags: {
    web: 'benefits_claims_lighthouse_provider_web',
    mobile: 'benefits_claims_lighthouse_provider_mobile'
  }
)

# CHAMPVA is web-only at this time — mobile flag should remain disabled.
# BenefitsClaims::Providers::ProviderRegistry.register(
#   :champva,
#   BenefitsClaims::Providers::Champva::ChampvaBenefitsClaimsProvider,
#   feature_flag: 'benefits_claims_champva_provider',
#   platform_flags: {
#     web: 'benefits_claims_champva_provider_web',
#     mobile: 'benefits_claims_champva_provider_mobile'
#   }
# )
