# frozen_string_literal: true

require 'concurrent/map'

module BenefitsDocuments
  module Providers
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
            feature_flag: options[:feature_flag]
          }.freeze
        end

        def enabled_providers(user = nil)
          registry.each.with_object([]) do |(name, provider), result|
            result << { name:, class: provider[:class] } if enabled?(name, user)
          end
        end

        def enabled?(provider_name, user = nil)
          provider = registry[provider_name]
          return false unless provider

          Flipper.enabled?(provider[:feature_flag], user)
        end

        def get(provider_name)
          registry[provider_name]
        end

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
          return if provider_class.included_modules.include?(BenefitsDocuments::Providers::BenefitsDocumentsProvider)

          raise ArgumentError,
                "#{provider_class} must include BenefitsDocuments::Providers::BenefitsDocumentsProvider module"
        end
      end
    end
  end
end
