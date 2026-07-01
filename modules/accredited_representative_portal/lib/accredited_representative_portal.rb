# frozen_string_literal: true

require 'accredited_representative_portal/engine'

module AccreditedRepresentativePortal
  ARP_USE_ACCREDITED_MODELS_FLAG = :arc_accredited_representative_portal_use_accredited_models

  # Single switch for the legacy Veteran::Service::* -> AccreditedX read-side migration.
  def self.use_accredited_models?
    Flipper.enabled?(ARP_USE_ACCREDITED_MODELS_FLAG)
  end
end
