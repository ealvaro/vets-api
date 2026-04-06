# frozen_string_literal: true

require 'benefits_claims/concerns/multi_provider_base'

# Web-specific implementation of multi-provider support for BenefitsClaimsController.
# Extends the shared BenefitsClaims::Concerns::MultiProviderBase with web-specific
# response formatting and metrics.
#
# Note: This concern references BenefitsClaimsController's STATSD_METRIC_PREFIX and
# STATSD_TAGS constants for metrics reporting. This coupling is intentional.
module V0
  module Concerns
    module MultiProviderSupport
      extend ActiveSupport::Concern
      include BenefitsClaims::Concerns::MultiProviderBase

      LEGACY_PROVIDER_TYPE_ALIASES = {
        'ivcchampvabenefitsclaimsprovider' => 'ivc_champva'
      }.freeze

      private

      def format_error_entry(provider_name, message)
        { 'provider' => provider_name, 'error' => message }
      end

      def format_get_claims_response(claims_data, errors)
        { 'data' => claims_data, 'meta' => { 'provider_errors' => errors.presence }.compact }
      end

      def statsd_metric_name(action)
        controller_class = self.class
        "#{controller_class::STATSD_METRIC_PREFIX}.#{action}"
      end

      def statsd_tags_for_provider(provider_name)
        controller_class = self.class
        controller_class::STATSD_TAGS + ["provider:#{provider_name}"]
      end

      # Overrides base implementation to use explicit routing instead of fallback iteration.
      #
      # Retrieves a claim from the appropriate provider based on provider_type parameter.
      #
      # The type parameter is optional and defaults to lighthouse for backward compatibility
      # with existing bookmarks/URLs. This means lighthouse claims can be accessed without
      # specifying type, even when multiple providers exist. Other providers require the
      # type parameter to be explicitly specified.
      #
      # For Lighthouse claims, routes through V0::LighthouseClaims::Proxy to apply
      # web-specific transforms. Other providers use their provider implementation directly.
      #
      # Rollout strategy: Frontend will deploy first to send type parameter, then we enable
      # the second provider. This ensures type is always present before it becomes required.
      def get_claim_from_providers(claim_id, provider_type = nil)
        # Default to lighthouse for backward compatibility when no type is specified.
        # All paths go through get_claim_for_provider_type for consistent error handling.
        get_claim_for_provider_type(claim_id, provider_type.presence || 'lighthouse')
      end

      # Routes claim request to appropriate implementation based on provider type.
      # Lighthouse uses Proxy (with web-specific transforms), others use provider directly.
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

      # Checks if a provider class is the Lighthouse provider
      def lighthouse_provider?(provider_class)
        provider_class.name.downcase.include?('lighthouse')
      end

      # Returns the web-specific Lighthouse Proxy
      # This proxy includes web transforms (rename_rv1, suppress_evidence_requests)
      def lighthouse_proxy
        @lighthouse_proxy ||= V0::LighthouseClaims::Proxy.new(@current_user)
      end

      def provider_platform
        :web
      end

      def provider_registry
        @provider_registry ||= BenefitsClaims::Providers::ProviderRegistry.enabled_providers(
          @current_user,
          platform: provider_platform
        )
      end

      def provider_class_for_type(type)
        provider_type = normalized_provider_type(type)
        provider = provider_registry.find { |p| p[:name].to_s == provider_type }

        raise Common::Exceptions::InvalidFieldValue.new('type', type) if provider.nil?

        provider[:class]
      end

      def supported_provider_types
        provider_registry.map { |p| p[:name].to_s }
      end

      # Override base implementation to add provider field to each claim
      # This enables the frontend to distinguish claims with identical IDs from different providers
      def extract_claims_data(provider_class, response)
        claims_data = super(provider_class, response)
        provider_type = provider_type_from_class(provider_class)

        # Add provider field to each claim
        claims_data.each do |claim|
          next unless claim.is_a?(Hash)

          claim['attributes'] ||= {}
          claim['attributes']['provider'] = provider_type
        end

        claims_data
      end

      # Maps provider class to provider type string via registry
      def provider_type_from_class(provider_class)
        provider = provider_registry.find { |p| p[:class] == provider_class }
        raise Common::Exceptions::InvalidFieldValue.new('provider_class', provider_class.to_s) if provider.nil?

        provider[:name].to_s
      end

      def normalized_provider_type(type)
        normalized_type = type.to_s.downcase
        LEGACY_PROVIDER_TYPE_ALIASES.fetch(normalized_type, normalized_type)
      end
    end
  end
end
