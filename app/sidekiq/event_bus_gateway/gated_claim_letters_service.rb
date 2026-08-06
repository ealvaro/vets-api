# frozen_string_literal: true

require 'lighthouse/benefits_documents/service'
require_relative 'gated_claim_letters_configuration'

module EventBusGateway
  # BenefitsDocuments::Service bound to the tighter-timeout gated config. Inherits
  # claim_letters_search (and everything else) unchanged; only the underlying
  # Faraday read timeout differs.
  class GatedClaimLettersService < BenefitsDocuments::Service
    configuration EventBusGateway::GatedClaimLettersConfiguration
  end
end
