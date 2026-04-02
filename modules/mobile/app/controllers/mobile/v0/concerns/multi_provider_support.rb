# frozen_string_literal: true

require 'benefits_claims/concerns/multi_provider_base'

# This concern provides multi-claim provider support for the mobile ClaimsAndAppealsController.
# It fetches claims from all enabled providers in the BenefitsClaims::Providers::ProviderRegistry
# and returns them in a format compatible with mobile's existing adapter and error handling.
#
# Unlike the web version (V0::Concerns::MultiProviderSupport), this concern:
# - Returns raw claims data that will be parsed by Mobile::V0::Adapters::ClaimsOverview
# - Uses mobile's error format: [{ service: 'provider_name', error_details: 'message' }]
# - Integrates with mobile's existing claims/appeals aggregation pattern
module Mobile
  module V0
    module Concerns
      module MultiProviderSupport
        extend ActiveSupport::Concern
        include BenefitsClaims::Concerns::MultiProviderBase

        private

        def format_error_entry(provider_name, message)
          {
            service: provider_name,
            error_details: message
          }
        end

        def format_get_claims_response(claims_data, errors)
          [claims_data, errors]
        end

        def statsd_metric_name(action)
          "mobile.claims_and_appeals.#{action}"
        end

        def statsd_tags_for_provider(provider_name)
          ["provider:#{provider_name}"]
        end

        # Overrides base implementation to use explicit routing instead of fallback iteration.
        #
        # Retrieves a claim from the appropriate provider based on provider_type parameter.
        #
        # The type parameter is optional and defaults to lighthouse for backward compatibility
        # with existing bookmarked URLs. This means lighthouse claims can be accessed without
        # specifying type, even when multiple providers exist. Other providers require the
        # type parameter to be explicitly specified to prevent ID collisions.
        #
        # For Lighthouse claims, routes through Mobile::V0::LighthouseClaims::Proxy to apply
        # mobile-specific transforms. Other providers use their provider implementation directly.
        def get_claim_from_providers(claim_id, provider_type = nil)
          # Default to lighthouse for backward compatibility when no type is specified.
          # All paths go through get_claim_for_provider_type for consistent error handling.
          get_claim_for_provider_type(claim_id, provider_type.presence || 'lighthouse')
        end

        # Routes claim request to appropriate implementation based on provider type.
        # Lighthouse uses Proxy (with mobile-specific transforms), others use provider directly.
        # Wraps provider calls with StatsD metrics and structured logging for ops visibility.
        def get_claim_for_provider_type(claim_id, provider_type)
          provider_class = provider_class_for_type(provider_type)

          if lighthouse_provider?(provider_class)
            lighthouse_proxy.get_claim(claim_id)
          else
            provider = provider_class.new(@current_user)
            provider.get_claim(claim_id)
          end
        rescue Common::Exceptions::RecordNotFound
          log_claim_not_found(provider_class)
          raise
        rescue Common::Exceptions::Unauthorized, Common::Exceptions::Forbidden,
               Common::Exceptions::InvalidFieldValue
          raise
        rescue => e
          handle_get_claim_error(provider_class, e)
          raise
        end

        def provider_platform
          :mobile
        end

        def provider_registry
          @provider_registry ||= BenefitsClaims::Providers::ProviderRegistry.enabled_providers(
            @current_user,
            platform: provider_platform
          )
        end

        def provider_class_for_type(type)
          normalized_type = type.to_s.downcase
          provider = provider_registry.find { |p| p[:name].to_s == normalized_type }

          raise Common::Exceptions::InvalidFieldValue.new('type', type) if provider.nil?

          provider[:class]
        end

        def supported_provider_types
          provider_registry.map { |p| p[:name].to_s }
        end

        # Override base implementation to add provider field to each claim
        def extract_claims_data(provider_class, response)
          claims_data = super(provider_class, response)
          provider_type = provider_type_from_class(provider_class)

          # Add provider field to each claim
          claims_data.each do |claim|
            claim['provider'] = provider_type if claim.is_a?(Hash)
          end

          claims_data
        end

        # Maps provider class to provider type string via registry
        def provider_type_from_class(provider_class)
          provider = provider_registry.find { |p| p[:class] == provider_class }
          raise Common::Exceptions::InvalidFieldValue.new('provider_class', provider_class.to_s) if provider.nil?

          provider[:name].to_s
        end

        # Checks if a provider class is the Lighthouse provider
        def lighthouse_provider?(provider_class)
          provider_class.name.downcase.include?('lighthouse')
        end

        # Returns the mobile-specific Lighthouse Proxy
        # This proxy includes mobile transforms (override_rv1, suppress_evidence_requests)
        # Note: The controller should also route to the appropriate adapter, as adapters
        # may contain provider-specific logic (e.g., status code mappings)
        def lighthouse_proxy
          @lighthouse_proxy ||= Mobile::V0::LighthouseClaims::Proxy.new(@current_user)
        end
      end
    end
  end
end
