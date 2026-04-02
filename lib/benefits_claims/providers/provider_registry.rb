# frozen_string_literal: true

require 'concurrent/map'

module BenefitsClaims
  module Providers
    # Centralized registry for managing multiple benefits claims data providers.
    #
    # The ProviderRegistry maintains a thread-safe collection of provider implementations
    # that can be dynamically enabled/disabled via feature flags.
    # This allows the application to aggregate claims data from multiple sources
    # (e.g., Lighthouse, CHAMPVA) without requiring code changes.
    #
    # ## Thread Safety
    # Uses Concurrent::Map for thread-safe concurrent access. Safe to call from
    # multiple threads without external synchronization.
    #
    # ## Provider Registration
    # Providers are registered with a unique name, class, and required configuration:
    # - feature_flag: (required) Master on/off flag for the provider regardless of platform
    # - platform_flags: Per-platform flags ({ web: 'flag_name', mobile: 'flag_name' })
    #
    # ## Feature Flag Behavior
    # A provider is considered enabled for a given platform when:
    # 1. The master feature_flag is enabled
    # 2. AND the platform-specific flag is enabled
    #
    # Missing platform flags always default to false — a provider will never be
    # displayed on a platform without an explicit platform flag toggled on.
    #
    # If no platform is specified, only the master flag is checked.
    #
    # ## Example Usage
    #   ProviderRegistry.register(
    #     :lighthouse,
    #     BenefitsClaims::Providers::Lighthouse::LighthouseBenefitsClaimsProvider,
    #     feature_flag: 'benefits_claims_lighthouse_provider',
    #     platform_flags: {
    #       web: 'benefits_claims_lighthouse_provider_web',
    #       mobile: 'benefits_claims_lighthouse_provider_mobile'
    #     }
    #   )
    #
    #   ProviderRegistry.register(
    #     :champva,
    #     BenefitsClaims::Providers::Champva::ChampvaBenefitsClaimsProvider,
    #     feature_flag: 'benefits_claims_champva_provider',
    #     platform_flags: {
    #       web: 'benefits_claims_champva_provider_web',
    #       mobile: 'benefits_claims_champva_provider_mobile'
    #     }
    #   )
    #
    #   # Get enabled providers for a platform
    #   ProviderRegistry.enabled_providers(current_user, platform: :web)
    #   # => [{ name: :lighthouse, class: LighthouseBenefitsClaimsProvider },
    #   #     { name: :champva,    class: ChampvaBenefitsClaimsProvider }]
    #
    #   ProviderRegistry.enabled_providers(current_user, platform: :mobile)
    #   # => [{ name: :lighthouse, class: LighthouseBenefitsClaimsProvider }]
    #
    class ProviderRegistry
      @registry = Concurrent::Map.new

      class << self
        attr_reader :registry
        private :registry

        def register(provider_name, provider_class, options = {})
          validate_provider_class!(provider_class)
          validate_feature_flag!(provider_name, options)

          registry[provider_name] = {
            class: provider_class,
            feature_flag: options[:feature_flag],
            platform_flags: options.fetch(:platform_flags, {}).to_h.freeze
          }.freeze
        end

        def enabled_providers(user = nil, platform: nil)
          registry.each.with_object([]) do |(name, provider), result|
            result << { name:, class: provider[:class] } if enabled?(name, user, platform:)
          end
        end

        def enabled_provider_classes(user = nil, platform: nil)
          registry.each.with_object([]) do |(name, provider), result|
            result << provider[:class] if enabled?(name, user, platform:)
          end
        end

        def enabled?(provider_name, user = nil, platform: nil)
          provider = registry[provider_name]
          return false unless provider

          return false unless Flipper.enabled?(provider[:feature_flag], user)
          return true unless platform

          platform_flag = provider[:platform_flags][platform]
          platform_flag ? Flipper.enabled?(platform_flag, user) : false
        end

        ##
        # Retrieves the configuration for a specific provider.
        # Useful for debugging in production environments (e.g., Argo console).
        #
        # @example
        #   config = ProviderRegistry.get(:lighthouse)
        #   # => { class: LighthouseBenefitsClaimsProvider, feature_flag: '...', platform_flags: { ... } }
        def get(provider_name)
          registry[provider_name]
        end

        # Clear all registered providers (useful for testing)
        def clear!
          raise 'ProviderRegistry.clear! cannot be called in production' if Rails.env.production?

          registry.clear
        end

        private

        def validate_feature_flag!(provider_name, options)
          return if options[:feature_flag].present?

          raise ArgumentError, "#{provider_name} must be registered with a feature_flag"
        end

        def validate_provider_class!(provider_class)
          unless provider_class.included_modules.include?(BenefitsClaims::Providers::BenefitsClaimsProvider)
            raise ArgumentError,
                  "#{provider_class} must include BenefitsClaims::Providers::BenefitsClaimsProvider module"
          end
        end
      end
    end
  end
end
