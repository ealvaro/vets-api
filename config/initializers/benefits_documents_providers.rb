# frozen_string_literal: true

require 'benefits_documents/providers/provider_registry'
require 'benefits_documents/providers/ivc_champva/ivc_champva_benefits_documents_provider'
require 'benefits_documents/providers/lighthouse/lighthouse_benefits_documents_provider'

BenefitsDocuments::Providers::ProviderRegistry.register(
  :lighthouse,
  BenefitsDocuments::Providers::Lighthouse::LighthouseBenefitsDocumentsProvider,
  feature_flag: 'benefits_documents_lighthouse_provider'
)

BenefitsDocuments::Providers::ProviderRegistry.register(
  :ivc_champva,
  BenefitsDocuments::Providers::IvcChampva::IvcChampvaBenefitsDocumentsProvider,
  feature_flag: 'benefits_documents_ivc_champva_provider'
)
