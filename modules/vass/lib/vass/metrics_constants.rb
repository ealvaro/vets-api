# frozen_string_literal: true

module Vass
  ##
  # Constants for StatsD metrics tracking throughout the VASS module.
  #
  # Naming Convention: api.vass.{layer}.{component}.{action}.{outcome}
  #
  # Layers:
  #   - controller: User-facing API endpoints (success/failure/total)
  #   - infrastructure: Rate limiting, OTP/session lifecycle, auth, availability soft outcomes
  #
  # Dual-count rule:
  #   Some user-error paths increment both an infrastructure counter and controller .failure
  #   (rate limits, invalid OTP, identity validation, OTP expired). Soft availability outcomes
  #   are infrastructure-only; use .total + infra counters for availability denominators.
  #
  # Tags (consistent across controller/infra metrics):
  #   - service:vass (always present)
  #   - endpoint:{action_name} (controller metrics)
  #   - http_method:{GET|POST} (controller metrics)
  #   - http_status:{200|400|401|404|500|502} (controller metrics)
  #   - error_type:{ErrorClassName|string_code} (failure metrics only)
  #   - reason:{token_reason} (JWT auth infrastructure failures)
  #
  module MetricsConstants
    # Base prefixes
    METRIC_PREFIX = 'api.vass'
    CONTROLLER_PREFIX = "#{METRIC_PREFIX}.controller".freeze
    INFRASTRUCTURE_PREFIX = "#{METRIC_PREFIX}.infrastructure".freeze

    # Service identification
    SERVICE_TAG = 'service:vass'

    # Outcome suffixes
    SUCCESS = 'success'
    FAILURE = 'failure'
    TOTAL = 'total'

    # ========================================
    # Controller Metrics - Sessions
    # ========================================
    SESSIONS_REQUEST_OTP = "#{CONTROLLER_PREFIX}.sessions.request_otp".freeze
    SESSIONS_AUTHENTICATE_OTP = "#{CONTROLLER_PREFIX}.sessions.authenticate_otp".freeze
    SESSIONS_REVOKE_TOKEN = "#{CONTROLLER_PREFIX}.sessions.revoke_token".freeze

    # ========================================
    # Controller Metrics - Appointments
    # ========================================
    APPOINTMENTS_AVAILABILITY = "#{CONTROLLER_PREFIX}.appointments.availability".freeze
    APPOINTMENTS_CREATE = "#{CONTROLLER_PREFIX}.appointments.create".freeze
    APPOINTMENTS_SHOW = "#{CONTROLLER_PREFIX}.appointments.show".freeze
    APPOINTMENTS_CANCEL = "#{CONTROLLER_PREFIX}.appointments.cancel".freeze
    APPOINTMENTS_TOPICS = "#{CONTROLLER_PREFIX}.appointments.topics".freeze

    # ========================================
    # Infrastructure Metrics - Rate Limiting
    # ========================================
    RATE_LIMIT_GENERATION_EXCEEDED = "#{INFRASTRUCTURE_PREFIX}.rate_limit.generation.exceeded".freeze
    RATE_LIMIT_VALIDATION_EXCEEDED = "#{INFRASTRUCTURE_PREFIX}.rate_limit.validation.exceeded".freeze

    # ========================================
    # Infrastructure Metrics - Session/OTP
    # ========================================
    SESSION_OTP_EXPIRED = "#{INFRASTRUCTURE_PREFIX}.session.otp.expired".freeze
    SESSION_OTP_INVALID = "#{INFRASTRUCTURE_PREFIX}.session.otp.invalid".freeze
    SESSION_JWT_EXPIRED = "#{INFRASTRUCTURE_PREFIX}.session.jwt.expired".freeze
    SESSION_JWT_MISSING = "#{INFRASTRUCTURE_PREFIX}.session.jwt.missing".freeze
    SESSION_JWT_INVALID = "#{INFRASTRUCTURE_PREFIX}.session.jwt.invalid".freeze
    SESSION_JWT_REVOKED = "#{INFRASTRUCTURE_PREFIX}.session.jwt.revoked".freeze

    # ========================================
    # Infrastructure Metrics - Auth Failures
    # ========================================
    AUTH_IDENTITY_VALIDATION_FAILURE = "#{INFRASTRUCTURE_PREFIX}.auth.identity_validation.failure".freeze
    AUTH_MISSING_EDIPI = "#{INFRASTRUCTURE_PREFIX}.auth.missing_edipi".freeze

    # ========================================
    # Infrastructure Metrics - Availability Scenarios
    # ========================================
    AVAILABILITY_NO_COHORTS = "#{INFRASTRUCTURE_PREFIX}.availability.no_cohorts".freeze
    AVAILABILITY_NEXT_COHORT = "#{INFRASTRUCTURE_PREFIX}.availability.next_cohort".freeze
    AVAILABILITY_ALREADY_BOOKED = "#{INFRASTRUCTURE_PREFIX}.availability.already_booked".freeze
    AVAILABILITY_NO_SLOTS = "#{INFRASTRUCTURE_PREFIX}.availability.no_slots_available".freeze
  end
end
