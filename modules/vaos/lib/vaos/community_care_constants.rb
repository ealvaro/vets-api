# frozen_string_literal: true

module VAOS
  # Constants used specifically for Community Care Appointments logging, metrics, and service identification
  # This module only contains constants that are shared across multiple files.
  # Constants used in only one file should remain local to that file.
  module CommunityCareConstants
    # Service identification constants
    CC_APPOINTMENTS = 'Community Care Appointments'
    COMMUNITY_CARE_SERVICE_TAG = 'service:community_care_appointments'

    # StatsD prefix for app-level Community Care metrics that we emit by hand.
    #
    # This is NOT the prefix used for outbound-client call metrics. Those come from
    # each client's own STATSD_KEY_PREFIX via Common::Client::Concerns::Monitoring
    # (Eps::BaseService => 'api.eps', Ccra::BaseService => 'api.ccra'), which appends
    # '.total' / '.fail' automatically.
    #
    # Consequence worth knowing before you build a dashboard: several Eps-namespaced
    # classes emit under 'api.vaos' rather than 'api.eps', because they use this
    # constant. In Datadog these arrive as vets_api.statsd.api_vaos_* (dots become
    # underscores; see config/initializers/statsd_instrument_monkeypatch.rb):
    #
    #   Eps::ProviderService                        -> api.vaos.provider_service.*
    #   Eps::AppointmentStatusNotificationCallback  -> api.vaos.appointment_status_notification.*
    #   Eps::AppointmentStatusJob                   -> api.vaos.appointment_status_check.*
    #   Eps::AppointmentStatusEmailJob              -> api.vaos.appointment_status_email_job.*
    #
    # The matching 'api.eps.*' names for those do not exist. Querying them returns
    # no data silently rather than erroring, which has already cost one dashboard.
    STATSD_PREFIX = 'api.vaos'
  end
end
