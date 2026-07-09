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

    # Claim-letter propagation-lag re-check offsets (measurement only). Each entry
    # enqueues one deferred LetterReadyClaimLetterRecheckJob at that offset after a
    # notification to sample whether a decision letter has since become available.
    # The label is used as a DataDog tag so a lag distribution can be built per offset.
    # The 3d/7d offsets exist to catch letters that don't land until after a weekend
    # (or holiday), so the tail isn't right-censored at 24h.
    CLAIM_LETTER_RECHECK_INTERVALS = {
      '15m' => 15.minutes,
      '1h' => 1.hour,
      '4h' => 4.hours,
      '24h' => 24.hours,
      '3d' => 3.days,
      '7d' => 7.days
    }.freeze

    # Recency window for the alternate "available" signal: a decision letter counts
    # as present-now when its received_at falls within this window of the re-check.
    # Logged alongside the set-change delta so we can compare the two definitions
    # against real data before committing to a gate (see story open question). This
    # signal keys off received_at, which is known to be unreliable (backdated /
    # future-dated) — hence it is measured, not yet trusted.
    CLAIM_LETTER_RECENCY_WINDOW = 7.days

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
