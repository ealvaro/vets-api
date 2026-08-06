# frozen_string_literal: true

require 'zlib'

module EventBusGateway
  module Constants
    # VA Notify service settings
    NOTIFY_SETTINGS = Settings.vanotify.services.benefits_management_tools

    # The following retry counts each used to be 16, which was causing production strain and staging strain.
    # Controls the sidekiq (infrastructure level) retry when the letter ready email job fails.
    SIDEKIQ_RETRY_COUNT_FIRST_EMAIL = 5
    # Controls the sidekiq (infrastructure level) retry when the letter ready email retry job fails.
    SIDEKIQ_RETRY_COUNT_RETRY_EMAIL = 3
    # Controls the maximum number of email attempts to VA notify (application level).
    MAX_EMAIL_ATTEMPTS = 5

    # Controls the sidekiq (infrastructure level) retry when the letter ready sms job fails.
    SIDEKIQ_RETRY_COUNT_FIRST_SMS = 5
    # Controls the sidekiq (infrastructure level) retry when the letter ready sms retry job fails.
    SIDEKIQ_RETRY_COUNT_RETRY_SMS = 3
    # Controls the maximum number of sms attempts to VA notify (application level).
    MAX_SMS_ATTEMPTS = 5

    # SMS blackout window: 9:00 PM – 9:00 AM Eastern (handles EST/EDT automatically)
    SMS_BLACKOUT_ZONE = ActiveSupport::TimeZone['Eastern Time (US & Canada)']
    SMS_BLACKOUT_START_HOUR = 21 # 9:00 PM Eastern
    SMS_BLACKOUT_END_HOUR = 9 # 9:00 AM Eastern

    def self.sms_blackout_period?
      current_hour = Time.current.in_time_zone(SMS_BLACKOUT_ZONE).hour
      current_hour >= SMS_BLACKOUT_START_HOUR || current_hour < SMS_BLACKOUT_END_HOUR
    end

    SMS_BLACKOUT_DEFER_DEFAULT_WINDOW_MINUTES = 180
    SMS_BLACKOUT_DEFER_DEFAULT_START_HOUR_EASTERN = 9

    def self.sms_blackout_defer_window_minutes
      value = Settings.vanotify.services.benefits_management_tools.sms_blackout_defer.window_minutes
      minutes = value.to_i
      minutes.positive? ? minutes : SMS_BLACKOUT_DEFER_DEFAULT_WINDOW_MINUTES
    end

    def self.sms_blackout_defer_start_hour_eastern
      value = Settings.vanotify.services.benefits_management_tools.sms_blackout_defer.delivery_start_hour_eastern
      hour = value.to_i
      (0..23).cover?(hour) ? hour : SMS_BLACKOUT_DEFER_DEFAULT_START_HOUR_EASTERN
    end

    # Deterministic, salt-free hash → minute offset in [0, window).
    # Same identifier always maps to the same slot for a given window width.
    def self.compute_blackout_defer_slot(identifier, window_minutes = sms_blackout_defer_window_minutes)
      minutes = window_minutes.to_i
      minutes = SMS_BLACKOUT_DEFER_DEFAULT_WINDOW_MINUTES unless minutes.positive?
      Zlib.crc32(identifier.to_s) % minutes
    end

    # Next delivery-window time in UTC for a given identifier. Picks the next
    # occurrence of start_hour Eastern (today if still upcoming, else tomorrow),
    # then adds the hashed minute offset.
    def self.next_blackout_defer_time(identifier)
      start_hour = sms_blackout_defer_start_hour_eastern
      slot_minutes = compute_blackout_defer_slot(identifier)

      now_eastern = Time.current.in_time_zone(SMS_BLACKOUT_ZONE)
      base = now_eastern.change(hour: start_hour, min: 0, sec: 0)
      base += 1.day if now_eastern >= base
      (base + slot_minutes.minutes).utc
    end

    # Controls the sidekiq (infrastructure level) retry when the letter ready push job fails.
    SIDEKIQ_RETRY_COUNT_FIRST_PUSH = 5

    # Controls the sidekiq (infrastructure level) retry when the letter ready notification job fails.
    SIDEKIQ_RETRY_COUNT_FIRST_NOTIFICATION = 5

    # Lighthouse/VBMS doc type id for a benefits decision letter (a.k.a. "184").
    DECISION_LETTER_DOC_TYPE = '184'

    # Recency window for the send-time "available" signal: at attempt 0 (no prior
    # snapshot to diff against) a decision letter counts as present-now when its
    # received_at falls within this window. On re-checks we key off the set-change
    # delta instead, which is the trusted signal (received_at is unreliable —
    # backdated / future-dated), so this window only decides the initial miss.
    CLAIM_LETTER_RECENCY_WINDOW = 7.days

    # --- Option A: gated send with re-check (see LetterReadyNotificationJob) -------
    # On a "miss" (no recent/new decision letter yet) the parent job defers the send
    # and re-enqueues itself on this interval up to this many attempts, then falls
    # back to sending anyway. Measurement (#146570) showed ~99% of misses resolve on
    # the first 15m re-check, so avg attempts ≈ 1. All three are tunable via Settings
    # (vanotify.services.benefits_management_tools.gated_send) without a code change;
    # the constants are the safe defaults when a Setting is absent/blank.
    GATED_SEND_DEFAULT_RECHECK_INTERVAL_MINUTES = 15
    GATED_SEND_DEFAULT_MAX_RECHECK_ATTEMPTS = 4
    GATED_SEND_DEFAULT_FALLBACK_SEND_ANYWAY = true
    # Read timeout (seconds) for the gate's Benefits Documents client, enforced as a
    # Faraday read_timeout on GatedClaimLettersConfiguration (not Ruby's Timeout,
    # which is unsafe to interrupt arbitrary code in Sidekiq). Prod claim-letters
    # search latency is sub-second (p95 ~0.6s, ~1.2s max over a month), so 10s is
    # deep headroom over any real call yet tight enough that a hung BD can't hold
    # the job / back up the Sidekiq queue. On timeout the gate fails open (send).
    GATED_SEND_BD_TIMEOUT_SECONDS = 10

    def self.gated_send_settings
      Settings.vanotify.services.benefits_management_tools.gated_send
    end

    def self.gated_send_recheck_interval_minutes
      minutes = gated_send_settings&.recheck_interval_minutes.to_i
      minutes.positive? ? minutes : GATED_SEND_DEFAULT_RECHECK_INTERVAL_MINUTES
    end

    def self.gated_send_max_recheck_attempts
      attempts = gated_send_settings&.max_recheck_attempts.to_i
      attempts.positive? ? attempts : GATED_SEND_DEFAULT_MAX_RECHECK_ATTEMPTS
    end

    def self.gated_send_fallback_send_anyway?
      value = gated_send_settings&.fallback_send_anyway
      return GATED_SEND_DEFAULT_FALLBACK_SEND_ANYWAY if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    # Hostname mapping for different environments
    HOSTNAME_MAPPING = {
      'dev-api.va.gov' => 'dev.va.gov',
      'staging-api.va.gov' => 'staging.va.gov',
      'api.va.gov' => 'www.va.gov'
    }.freeze

    # DataDog tags for event bus gateway services
    DD_TAGS = [
      'service:event-bus-gateway',
      'team:cross-benefits-crew',
      'team:benefits',
      'itportfolio:benefits-delivery',
      'dependency:va-notify'
    ].freeze
  end
end
