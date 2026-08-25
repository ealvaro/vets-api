# frozen_string_literal: true

# NOTE: We're not using VANotify::DefaultCallback here because it currently only supports
# instrumentation for Zero Silent Failure (ZSF) events—specifically when notification_type == 'error'.
# This custom callback expands observability by capturing metrics for all delivery statuses.
#
# If DefaultCallback is updated in the future to support broader metadata-driven instrumentation,
# we could simplify by switching back to it.
#
module AccreditedRepresentativePortal
  class EmailDeliveryStatusCallback
    # Matches the placeholder addresses generated in Staging by
    # Representatives::Update#build_fake_email_attributes (e.g. "representative-123@example.com").
    FAKE_EMAIL_PATTERN = /\Arepresentative-[^@]+@example\.com\z/i

    # VA Notify status_reasons that indicate the failure was specifically caused by an
    # undeliverable/invalid recipient address. Includes both the legacy phrasing documented
    # in the Error Status Reason Mapping table:
    # https://va.ghe.com/software/vanotify-team/blob/main/Support/error_status_reason_mapping.md
    # and the current STATUS_REASON_* constants emitted by notification-api:
    # https://va.ghe.com/software/notification-api/blob/main/app/constants.py
    ADDRESS_FAILURE_STATUS_REASONS = [
      # Legacy phrasing
      'Failed to deliver email due to hard bounce',
      'Email address is in invalid format',
      'Temporarily failed to deliver email due to soft bounce',
      # Current notification-api phrasing
      'Undeliverable - Individual unreachable',
      'Undeliverable - Unable to deliver',
      'Undeliverable - Individual or carrier has blocked the request'
    ].freeze

    def self.call(notification)
      tags = extract_tags(notification)
      tags = tags.merge('recipient_type' => 'test') if fake_email_failure?(notification)
      base_metric = 'api.vanotify.notifications'

      case notification.status
      when 'delivered'
        report_success(base_metric, tags)
      when 'permanent-failure', 'temporary-failure'
        report_failure(notification, base_metric, tags)
      else
        report_other(notification, base_metric, tags)
      end
    end

    # Only tags a failure as coming from a known Staging placeholder address when the failure
    # reason itself is address-related. This avoids masking unrelated bugs (e.g. template or
    # provider errors) that happen to occur while sending to a fake address.
    def self.fake_email_failure?(notification)
      address_related_failure?(notification) && fake_email_address?(notification)
    end

    def self.fake_email_address?(notification)
      FAKE_EMAIL_PATTERN.match?(notification.to.to_s)
    rescue
      false
    end

    def self.address_related_failure?(notification)
      %w[permanent-failure temporary-failure].include?(notification.status) &&
        ADDRESS_FAILURE_STATUS_REASONS.include?(notification.status_reason)
    end

    def self.extract_tags(notification)
      metadata = begin
        notification.callback_metadata.to_h.deep_stringify_keys
      rescue
        {}
      end

      statsd_tags = metadata['statsd_tags'] || {}

      # Ensure both keys and values are strings
      tags = statsd_tags.to_h { |k, v| [k.to_s, v.to_s] }

      # Provide fallback if tags are missing or empty
      tags.presence || {
        'service' => 'va_notify',
        'function' => "callback_status_#{notification.notification_type || 'unknown'}"
      }
    end

    def self.report_success(base_metric, tags)
      StatsD.increment("#{base_metric}.delivered", tags:)
      StatsD.increment('silent_failure_avoided', tags:)
    end

    def self.report_failure(notification, base_metric, tags)
      StatsD.increment("#{base_metric}.#{notification.status}", tags:)
      Rails.logger.error(build_log_payload(notification, tags).to_json)
    end

    def self.report_other(notification, base_metric, tags)
      StatsD.increment("#{base_metric}.other", tags:)
      Rails.logger.warn(build_log_payload(notification, tags).merge(message: 'Unhandled callback status').to_json)
    end

    def self.build_log_payload(notification, tags)
      {
        notification_id: notification.notification_id,
        notification_type: notification.notification_type,
        status: notification.status,
        status_reason: notification.status_reason,
        callback_klass: notification.callback_klass,
        tags:,
        metadata: notification.callback_metadata.to_h,
        source_location: notification.source_location,
        timestamp: Time.current
      }
    end
  end
end
