# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/attr_package'
require 'claim_letters/providers/claim_letters/lighthouse_claim_letters_provider'
require_relative 'constants'
require_relative 'errors'
require_relative 'letter_ready_job_concern'
require_relative 'letter_ready_email_job'
require_relative 'letter_ready_push_job'
require_relative 'letter_ready_sms_job'

module EventBusGateway
  class LetterReadyNotificationJob
    include Sidekiq::Job
    include LetterReadyJobConcern

    STATSD_METRIC_PREFIX = 'event_bus_gateway.letter_ready_notification'

    # Lighthouse/VBMS doc type id for a benefits decision letter (a.k.a. "184").
    DECISION_LETTER_DOC_TYPE = '184'

    sidekiq_options retry: Constants::SIDEKIQ_RETRY_COUNT_FIRST_NOTIFICATION

    sidekiq_retries_exhausted do |msg, _ex| # rubocop:disable Cop/AttrPackageDeleteAfterRetry
      job_id = msg['jid']
      error_class = msg['error_class']
      error_message = msg['error_message']
      timestamp = Time.now.utc

      ::Rails.logger.error('LetterReadyNotificationJob retries exhausted',
                           { job_id:, timestamp:, error_class:, error_message: })
      tags = Constants::DD_TAGS + ["function: #{error_message}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.exhausted", tags:)
    end

    def perform(participant_id, email_template_id = nil, push_template_id = nil, sms_template_id = nil) # rubocop:disable Cop/AttrPackageDeleteOnSuccess
      # Fetch participant data upfront
      icn = get_icn(participant_id)

      # Snapshot the most recent claim letter visible for this user as the
      # decision-letter event arrives (logging only; never affects the send).
      log_most_recent_claim_letter(icn)

      # Determine which notification types are requested based on template IDs
      requested_types = requested_notification_types(email_template_id, sms_template_id, push_template_id)

      errors = []
      errors << handle_email_notification(participant_id, email_template_id, icn)
      errors << handle_sms_notification(participant_id, sms_template_id, icn)
      errors << handle_push_notification(participant_id, push_template_id, icn)
      errors.compact!

      log_completion(email_template_id, push_template_id, sms_template_id, errors)
      handle_errors(errors, requested_types, icn)

      errors
    rescue => e
      # Only catch errors from the initial BGS/MPI lookups
      if e.is_a?(Errors::BgsPersonNotFoundError) ||
         e.is_a?(Errors::MpiProfileNotFoundError) ||
         @bgs_person.nil? || @mpi_profile.nil?
        record_notification_send_failure(e, 'Notification')
      end
      raise
    end

    private

    def requested_notification_types(email_template_id, sms_template_id, push_template_id)
      types = []
      types << 'email' if email_template_id.present?
      types << 'sms' if sms_template_id.present?
      types << 'push' if push_template_id.present?
      types
    end

    # Logs the most recent claim letter available for the user when the decision
    # letter event arrives. Gated behind a feature flag and fully guarded: any
    # failure here is logged but never interrupts the notification flow.
    def log_most_recent_claim_letter(icn)
      return if icn.blank?
      return unless Flipper.enabled?(:event_bus_gateway_log_most_recent_claim_letter, Flipper::Actor.new(icn))

      user = build_user_from_icn(icn, uuid: user_account(icn)&.id)
      letters = claim_letters_service(user).get_letters || []

      ::Rails.logger.info('LetterReadyNotificationJob most recent claim letter',
                          most_recent_claim_letter_payload(letters))
    rescue => e
      handle_claim_letter_log_error(e)
    end

    def most_recent_claim_letter_payload(letters)
      decision_letters = letters.select { |d| d[:doc_type] == DECISION_LETTER_DOC_TYPE }
      most_recent = most_recent_letter(letters)
      most_recent_decision = most_recent_letter(decision_letters)

      {
        message_type: 'ebg.letter_ready.most_recent_claim_letter',
        letter_count: letters.size,
        decision_letter_count: decision_letters.size,
        most_recent_received_at: format_letter_date(most_recent&.dig(:received_at)),
        most_recent_upload_date: format_letter_date(most_recent&.dig(:upload_date)),
        most_recent_doc_type: most_recent&.dig(:doc_type),
        most_recent_type_description: most_recent&.dig(:type_description),
        most_recent_document_id: most_recent&.dig(:document_id),
        most_recent_decision_received_at: format_letter_date(most_recent_decision&.dig(:received_at)),
        most_recent_decision_document_id: most_recent_decision&.dig(:document_id)
      }
    end

    def handle_claim_letter_log_error(error)
      ::Rails.logger.warn(
        'LetterReadyNotificationJob failed to log most recent claim letter',
        { error_class: error.class.name, error_message: Logging::Helper::DataScrubber.scrub(error.message) }
      )
      tags = Constants::DD_TAGS + ["error:#{error.class.name}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.most_recent_claim_letter_failure", tags:)
      nil
    end

    # Returns the letter with the newest received_at. Computes the max rather than
    # trusting provider sort order; falls back to the first letter if none are dated.
    def most_recent_letter(letters)
      return nil if letters.blank?

      dated = letters.select { |d| d[:received_at].present? }
      return letters.first if dated.empty?

      dated.max_by { |d| d[:received_at].to_datetime }
    end

    def format_letter_date(value)
      return nil if value.blank?

      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end

    # Builds a minimal LOA3 user from the ICN so the claim letters providers can
    # resolve participant_id/file_number via MPI, mirroring a real page request.
    # Uses the UserAccount UUID when available so provider log lines correlate
    # back to the veteran; falls back to a random UUID when there's no account.
    def build_user_from_icn(icn, uuid: nil)
      uuid = SecureRandom.uuid if uuid.blank?
      user_identity = UserIdentity.new(
        icn:,
        uuid:,
        loa: { current: 3, highest: 3 }
      )
      user = User.new(uuid: user_identity.uuid)
      user.instance_variable_set(:@identity, user_identity)
      user
    end

    # Always uses the Lighthouse Benefits Documents provider (the strategic
    # claim-letters source) regardless of the VBMS migration flag.
    def claim_letters_service(user)
      LighthouseClaimLettersProvider.new(user)
    end

    def should_send_email?(email_template_id, icn)
      email_template_id.present? && icn.present?
    end

    def should_send_push?(push_template_id, icn)
      push_template_id.present? && icn.present?
    end

    def should_send_sms?(sms_template_id, icn)
      sms_template_id.present? && icn.present?
    end

    def handle_email_notification(participant_id, email_template_id, icn)
      if should_send_email?(email_template_id, icn)
        first_name = get_first_name_from_participant_id(participant_id)

        if first_name.present?
          send_email_async(participant_id, email_template_id, first_name, icn)
        else
          log_notification_skipped('email', 'first_name not present', email_template_id)
          nil
        end
      else
        log_notification_skipped('email', 'ICN or template not available', email_template_id)
        nil
      end
    end

    def handle_sms_notification(participant_id, sms_template_id, icn)
      unless should_send_sms?(sms_template_id, icn)
        log_notification_skipped('sms', 'ICN or template not available', sms_template_id)
        return nil
      end

      unless Flipper.enabled?(:event_bus_gateway_letter_ready_sms_notifications, Flipper::Actor.new(icn))
        log_notification_skipped('sms', 'SMS notifications not enabled for this user', sms_template_id)
        return nil
      end

      send_sms_async(participant_id, sms_template_id, icn)
    end

    def handle_push_notification(participant_id, push_template_id, icn)
      unless should_send_push?(push_template_id, icn)
        log_notification_skipped('push', 'ICN or template not available', push_template_id)
        return nil
      end

      unless Flipper.enabled?(:event_bus_gateway_letter_ready_push_notifications, Flipper::Actor.new(icn))
        log_notification_skipped('push', 'Push notifications not enabled for this user', push_template_id)
        return nil
      end

      send_push_async(participant_id, push_template_id, icn)
    end

    def send_email_async(participant_id, email_template_id, first_name, icn)
      # Store PII in Redis and pass only cache key to avoid PII exposure in logs
      cache_key = Sidekiq::AttrPackage.create(first_name:, icn:)
      LetterReadyEmailJob.perform_async(participant_id, email_template_id, cache_key)
      nil
    rescue => e
      log_notification_failure('email', email_template_id, e)
      { type: 'email', error: e.message }
    end

    def send_sms_async(participant_id, sms_template_id, icn)
      # Store PII in Redis and pass only cache key to avoid PII exposure in logs
      cache_key = Sidekiq::AttrPackage.create(icn:)
      LetterReadySmsJob.perform_async(participant_id, sms_template_id, cache_key)
      nil
    rescue => e
      log_notification_failure('sms', sms_template_id, e)
      { type: 'sms', error: e.message }
    end

    def send_push_async(participant_id, push_template_id, icn)
      # Store PII in Redis and pass only cache key to avoid PII exposure in logs
      cache_key = Sidekiq::AttrPackage.create(icn:)
      LetterReadyPushJob.perform_async(participant_id, push_template_id, cache_key)
      nil
    rescue => e
      log_notification_failure('push', push_template_id, e)
      { type: 'push', error: e.message }
    end

    def log_notification_failure(notification_type, template_id, error)
      ::Rails.logger.error(
        "LetterReadyNotificationJob #{notification_type} enqueue failed",
        {
          notification_type:,
          template_id:,
          error_class: error.class.name,
          error_message: error.message
        }
      )

      # Track enqueuing failures (different from send failures tracked in child jobs)
      tags = Constants::DD_TAGS + [
        "notification_type:#{notification_type}",
        "error:#{error.class.name}"
      ]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.enqueue_failure", tags:)
    end

    def log_notification_skipped(notification_type, reason, template_id)
      ::Rails.logger.error(
        "LetterReadyNotificationJob #{notification_type} skipped",
        {
          notification_type:,
          reason:,
          template_id:
        }
      )

      tags = Constants::DD_TAGS + [
        "notification_type:#{notification_type}",
        "reason:#{reason.parameterize.underscore}"
      ]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.skipped", tags:)
    end

    def log_completion(email_template_id, push_template_id, sms_template_id, errors)
      successful_notifications = []
      successful_notifications << 'email' if email_template_id.present? && errors.none? { |e| e[:type] == 'email' }
      successful_notifications << 'push' if push_template_id.present? && errors.none? { |e| e[:type] == 'push' }
      successful_notifications << 'sms' if sms_template_id.present? && errors.none? { |e| e[:type] == 'sms' }

      failed_messages = errors.map { |h| "#{h[:type]}: #{h[:error]}" }.join(', ')

      ::Rails.logger.info(
        'LetterReadyNotificationJob completed',
        {
          notifications_sent: successful_notifications.join(', '),
          notifications_failed: failed_messages,
          email_template_id:,
          push_template_id:,
          sms_template_id:
        }
      )
    end

    def handle_errors(errors, requested_types, icn)
      return if errors.empty?

      failed_types = errors.map { |e| e[:type] }

      # Filter requested types by feature flags (some may have been skipped)
      # SMS and push may not be attempted even if template_id was provided if feature flag is off
      actually_requested_types = filter_by_feature_flags(requested_types, icn)

      # Check if all requested (and not feature-flag-skipped) notifications failed
      if actually_requested_types.present? && (failed_types.to_set == actually_requested_types.to_set)
        # All actually requested notifications failed to enqueue
        error_details = errors.map { |e| "#{e[:type]}: #{e[:error]}" }.join('; ')
        raise Errors::NotificationEnqueueError, "All notifications failed to enqueue: #{error_details}"
      else
        # Partial failure - some succeeded
        successful_types = actually_requested_types - failed_types
        error_messages = errors.map { |h| "#{h[:type]}: #{h[:error]}" }.join(', ')

        ::Rails.logger.warn(
          'LetterReadyNotificationJob partial failure',
          {
            successful: successful_types.join(', '),
            failed: error_messages
          }
        )
      end
    end

    def filter_by_feature_flags(requested_types, icn)
      actually_requested_types = requested_types.dup

      if requested_types.include?('sms') &&
         !Flipper.enabled?(:event_bus_gateway_letter_ready_sms_notifications, Flipper::Actor.new(icn))
        actually_requested_types.delete('sms')
      end

      if requested_types.include?('push') &&
         !Flipper.enabled?(:event_bus_gateway_letter_ready_push_notifications, Flipper::Actor.new(icn))
        actually_requested_types.delete('push')
      end

      actually_requested_types
    end
  end
end
