# frozen_string_literal: true

require 'rails_helper'
require 'benefits_documents/providers/document_upload_router'

RSpec.describe BenefitsDocuments::Providers::DocumentUploadRouter do
  subject(:router) { described_class.new(user) }

  let(:user) { build(:user, :loa3) }
  let(:params) { { claim_id: '123', file: 'file' } }
  let(:provider_instance) { instance_double(BenefitsDocuments::Providers::BenefitsDocumentsProvider) }
  let(:provider_class) { double('ProviderClass', new: provider_instance) }
  let(:lighthouse_instance) { instance_double(BenefitsDocuments::Providers::BenefitsDocumentsProvider) }
  let(:claim_ownership_resolver) { instance_double(BenefitsDocuments::Providers::ClaimOwnershipResolver) }

  before do
    allow(provider_instance).to receive(:queue_document_upload).and_return('provider-jid')
    allow(lighthouse_instance).to receive(:queue_document_upload).and_return('lighthouse-jid')
    allow(BenefitsDocuments::Providers::ClaimOwnershipResolver).to receive(:new)
      .and_return(claim_ownership_resolver)
    allow(BenefitsDocuments::Providers::Lighthouse::LighthouseBenefitsDocumentsProvider)
      .to receive(:new)
      .with(user)
      .and_return(lighthouse_instance)
    allow(Rails.logger).to receive(:info)
  end

  describe '#queue_document_upload' do
    it 'routes to the enabled Lighthouse provider by default' do
      allow(claim_ownership_resolver).to receive(:provider_for).with(params).and_return(:lighthouse)
      allow(BenefitsDocuments::Providers::ProviderRegistry).to receive(:enabled_providers)
        .with(user)
        .and_return([{ name: :lighthouse, class: provider_class }])

      result = router.queue_document_upload(params)

      expect(result).to eq('provider-jid')
      expect(provider_class).to have_received(:new).with(user)
      expect(provider_instance).to have_received(:queue_document_upload).with(params)
      expect(Rails.logger).to have_received(:info).with(
        described_class::ROUTING_LOG_MESSAGE,
        requested_provider: :lighthouse,
        selected_provider: :lighthouse,
        lighthouse_fallback: false
      )
    end

    it 'routes to an enabled requested provider' do
      champva_params = params.merge(provider: 'ivc_champva')
      allow(claim_ownership_resolver).to receive(:provider_for).with(champva_params).and_return(:ivc_champva)
      allow(BenefitsDocuments::Providers::ProviderRegistry).to receive(:enabled_providers)
        .with(user)
        .and_return([{ name: :ivc_champva, class: provider_class }])

      result = router.queue_document_upload(champva_params)

      expect(result).to eq('provider-jid')
      expect(provider_class).to have_received(:new).with(user)
      expect(provider_instance).to have_received(:queue_document_upload).with(champva_params)
      expect(Rails.logger).to have_received(:info).with(
        described_class::ROUTING_LOG_MESSAGE,
        requested_provider: :ivc_champva,
        selected_provider: :ivc_champva,
        lighthouse_fallback: false
      )
    end

    it 'falls back to Lighthouse when the requested provider is not enabled' do
      unknown_provider_params = params.merge(provider: 'unknown')
      allow(claim_ownership_resolver).to receive(:provider_for).with(unknown_provider_params).and_return(:unknown)
      allow(BenefitsDocuments::Providers::ProviderRegistry).to receive(:enabled_providers)
        .with(user)
        .and_return([{ name: :ivc_champva, class: provider_class }])

      result = router.queue_document_upload(unknown_provider_params)

      expect(result).to eq('lighthouse-jid')
      expect(BenefitsDocuments::Providers::Lighthouse::LighthouseBenefitsDocumentsProvider)
        .to have_received(:new).with(user)
      expect(lighthouse_instance).to have_received(:queue_document_upload).with(unknown_provider_params)
      expect(Rails.logger).to have_received(:info).with(
        described_class::ROUTING_LOG_MESSAGE,
        requested_provider: :unknown,
        selected_provider: :lighthouse,
        lighthouse_fallback: true
      )
    end

    it 'falls back to Lighthouse when no providers are enabled' do
      allow(claim_ownership_resolver).to receive(:provider_for).with(params).and_return(:lighthouse)
      allow(BenefitsDocuments::Providers::ProviderRegistry).to receive(:enabled_providers)
        .with(user)
        .and_return([])

      result = router.queue_document_upload(params)

      expect(result).to eq('lighthouse-jid')
      expect(BenefitsDocuments::Providers::Lighthouse::LighthouseBenefitsDocumentsProvider)
        .to have_received(:new).with(user)
      expect(lighthouse_instance).to have_received(:queue_document_upload).with(params)
      expect(Rails.logger).to have_received(:info).with(
        described_class::ROUTING_LOG_MESSAGE,
        requested_provider: :lighthouse,
        selected_provider: :lighthouse,
        lighthouse_fallback: true
      )
    end
  end
end
