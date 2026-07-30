# frozen_string_literal: true

require 'benefits_documents/providers/benefits_documents_provider'
require 'benefits_documents/providers/claim_ownership_resolver'
require 'benefits_documents/providers/lighthouse/lighthouse_benefits_documents_provider'
require 'benefits_documents/providers/provider_registry'

module BenefitsDocuments
  module Providers
    class DocumentUploadRouter
      include BenefitsDocuments::Providers::BenefitsDocumentsProvider

      DEFAULT_PROVIDER = :lighthouse
      ROUTING_LOG_MESSAGE = 'Benefits document upload provider selected'

      def initialize(current_user)
        @current_user = current_user
      end

      def queue_document_upload(params)
        provider_class(params).new(current_user).queue_document_upload(params)
      end

      private

      attr_reader :current_user

      def provider_class(params)
        requested_provider = requested_provider_name(params)
        provider = enabled_provider(requested_provider)
        selected_provider = provider ? provider[:name] : DEFAULT_PROVIDER
        lighthouse_fallback = provider.nil?

        Rails.logger.info(
          ROUTING_LOG_MESSAGE,
          requested_provider:,
          selected_provider:,
          lighthouse_fallback:
        )

        return provider[:class] unless lighthouse_fallback

        BenefitsDocuments::Providers::Lighthouse::LighthouseBenefitsDocumentsProvider
      end

      def enabled_provider(provider_name)
        enabled_providers.find { |provider| provider[:name] == provider_name }
      end

      def enabled_providers
        @enabled_providers ||= BenefitsDocuments::Providers::ProviderRegistry.enabled_providers(current_user)
      end

      def requested_provider_name(params)
        claim_ownership_resolver.provider_for(params)
      end

      def claim_ownership_resolver
        @claim_ownership_resolver ||= BenefitsDocuments::Providers::ClaimOwnershipResolver.new
      end
    end
  end
end
