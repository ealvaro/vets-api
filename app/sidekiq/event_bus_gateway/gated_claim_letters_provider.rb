# frozen_string_literal: true

require 'claim_letters/providers/claim_letters/lighthouse_claim_letters_provider'
require_relative 'gated_claim_letters_service'

module EventBusGateway
  # LighthouseClaimLettersProvider that talks to BD through the tighter-timeout
  # gated service. Reuses all of the parent's letter transformation; only swaps the
  # BD service instance so the gate's availability check is bounded by the gated
  # config's Faraday read timeout instead of the default 65s.
  class GatedClaimLettersProvider < LighthouseClaimLettersProvider
    def initialize(user, allowed_doctypes = nil)
      super
      @service = GatedClaimLettersService.new(user)
    end
  end
end
