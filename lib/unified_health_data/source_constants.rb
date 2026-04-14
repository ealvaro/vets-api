# frozen_string_literal: true

module UnifiedHealthData
  # Constants used across the UHD integration layer.
  #
  # Data-source identifiers (VISTA, ORACLE_HEALTH) appear in the SCDF API
  # response envelope (e.g. body['vista'], body['oracle-health']) and are
  # tagged onto each record's 'source' attribute for downstream consumers.
  #
  # Client-application identifiers (VAGOV, VAHB) are sent as the
  # x-mhv-client-application outbound header so the UHD backend can
  # distinguish traffic sources for analytics.
  module SourceConstants
    VISTA = 'vista'
    ORACLE_HEALTH = 'oracle-health'

    # Client application identifiers sent via the x-mhv-client-application header
    # so the UHD backend can distinguish traffic sources for analytics.
    VAGOV = 'VAGOV'
    VAHB = 'VAHB'
  end
end
