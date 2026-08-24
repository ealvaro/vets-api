# frozen_string_literal: true

module ClaimsEvidence
  module Metrics
    PREFIX = 'api.claims_evidence'
    # Ownership tags for every claims evidence metric, wherever it is emitted, so dashboards
    # and routing pick all of them up rather than just the ones the controller sends.
    TAGS = [
      'service:claims-evidence',
      'team:benefits-management-tools',
      'itportfolio:benefits-delivery',
      'dependency:claims-evidence-api'
    ].freeze
  end
end
