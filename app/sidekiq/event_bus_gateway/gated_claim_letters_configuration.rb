# frozen_string_literal: true

require 'lighthouse/benefits_documents/configuration'
require_relative 'constants'

module EventBusGateway
  # Benefits Documents client config for the gated send's availability check.
  # Identical to BenefitsDocuments::Configuration except for a tighter Faraday read
  # timeout: the gate runs in Sidekiq and must never hold a worker on a slow BD
  # call, and prod latency for claim-letters/search is sub-second (p95 ~0.6s, ~1.2s
  # max over a month), so a short read timeout has deep headroom over any real call.
  #
  # read_timeout is a class_attribute on the base config, so overriding it here
  # changes only this subclass. service_name is inherited ('BenefitsDocuments'), so
  # breakers and the external_service:benefitsdocuments metrics stay shared with the
  # primary client — one upstream, one circuit.
  class GatedClaimLettersConfiguration < BenefitsDocuments::Configuration
    self.read_timeout = Constants::GATED_SEND_BD_TIMEOUT_SECONDS
  end
end
