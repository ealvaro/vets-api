# frozen_string_literal: true

module VANotify
  # Delivery-result handler for the in-progress form reminder emails.
  #
  # These sends carry notification_type 'in_progress_reminder', which DefaultCallback deliberately
  # ignores: silent_failure counts failures to tell a veteran that something of theirs went wrong,
  # and a reminder to finish a form is not that. Counting reminders there would also add every
  # delivered reminder to silent_failure_avoided. So they get their own measure here instead.
  #
  # Runs alongside DefaultCallback, dispatched by VANotify::CustomCallback.
  class InProgressFormReminderCallback
    STATSD_PREFIX = 'api.vanotify.in_progress_form_reminder'

    # Total sends allowed for one reminder, including the first. These are time-sensitive nudges
    # rather than transactional mail, so one re-send is the useful ceiling.
    MAX_ATTEMPTS = 2
    RETRY_DELAY = 1.hour

    # Failures are expected outcomes here — mostly veterans with no address on file — rather than
    # application faults, so they are logged at warn and counted, not raised as errors.
    def self.call(notification)
      tags = statsd_tags(notification)

      case notification.status
      when 'delivered'
        StatsD.increment("#{STATSD_PREFIX}.delivered", tags:)
      when 'permanent-failure'
        StatsD.increment("#{STATSD_PREFIX}.permanent_failure", tags:)
        Rails.logger.warn('VANotify in progress reminder undelivered', log_payload(notification))
      when 'temporary-failure'
        StatsD.increment("#{STATSD_PREFIX}.temporary_failure", tags:)
        Rails.logger.warn('VANotify in progress reminder undelivered', log_payload(notification))
        retry_reminder(notification, tags) if Flipper.enabled?(:in_progress_form_reminder_retry)
      else
        StatsD.increment("#{STATSD_PREFIX}.other", tags:)
        Rails.logger.warn('VANotify in progress reminder unhandled status', log_payload(notification))
      end
    end

    # VA Notify reports these as "Retryable ... Replay the request", but replaying is the sender's
    # job and nothing was doing it. Re-run the reminder rather than re-sending the same payload:
    # perform re-checks that the form still exists — a veteran who submitted in the meantime no
    # longer has one — and re-derives the personalisation.
    #
    # The retry is anchored to a single form id, the one the original send was built around. For a
    # multi-form reminder that is the oldest form, so submitting it drops the retry even though the
    # veteran still has others in progress. That is the intended trade: the next scheduled sweep
    # picks the remaining forms up, and a dropped nudge costs less than a wrong one.
    def self.retry_reminder(notification, tags)
      metadata = callback_metadata(notification)
      in_progress_form_id = metadata['in_progress_form_id']
      attempt = metadata['attempt'].to_i

      # Sends queued before this shipped carry neither key, so they cannot be re-run. Counted so the
      # rollout window does not just look like temporary failures that were silently ignored.
      if in_progress_form_id.blank?
        StatsD.increment("#{STATSD_PREFIX}.retry_skipped", tags:)
        return
      end

      if attempt >= MAX_ATTEMPTS
        StatsD.increment("#{STATSD_PREFIX}.retries_exhausted", tags:)
        Rails.logger.warn('VANotify in progress reminder retries exhausted',
                          log_payload(notification).merge(attempt:, max_attempts: MAX_ATTEMPTS))
        return
      end

      VANotify::InProgressFormReminder.perform_in(RETRY_DELAY, in_progress_form_id, attempt + 1)
      StatsD.increment("#{STATSD_PREFIX}.retry_queued", tags:)
    rescue => e
      # CustomCallback swallows anything raised here and logs it at info, so without this the
      # reminder would be dropped with no usable signal. Unlike a delivery failure this is a system
      # fault, so it is logged at error.
      StatsD.increment("#{STATSD_PREFIX}.retry_queue_failed", tags:)
      Rails.logger.error('VANotify in progress reminder retry could not be queued',
                         log_payload(notification).merge(error: e.message))
      raise
    end

    # Carries the sender's service/function through, plus the form and the reason VA Notify gave.
    # The reason is the point: it separates the share that is retryable from the share that is a
    # missing address, which no reminder logic can fix.
    def self.statsd_tags(notification)
      metadata = callback_metadata(notification)
      tags = (metadata['statsd_tags'] || {}).map { |key, value| "#{key}:#{value}" }
      tags << "form_number:#{metadata['form_number']}" if metadata['form_number'].present?
      tags << "reason:#{reason_tag(notification)}"
      tags
    end

    # parameterize treats a hyphen as a word character, so "Undeliverable - Individual unreachable"
    # would tag as "undeliverable_-_individual_unreachable". Fold the separators together so the
    # facet reads cleanly.
    def self.reason_tag(notification)
      reason = notification.status_reason.presence
      return 'none' if reason.blank?

      reason.parameterize(separator: '_').tr('-', '_').squeeze('_')
    end

    def self.callback_metadata(notification)
      notification.callback_metadata.to_h.deep_stringify_keys
    rescue
      {}
    end

    def self.log_payload(notification)
      {
        notification_id: notification.notification_id,
        template_id: notification.template_id,
        status: notification.status,
        status_reason: notification.status_reason,
        form_number: callback_metadata(notification)['form_number']
      }
    end
  end
end
