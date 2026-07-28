# frozen_string_literal: true

require 'claims_api/jwt_encoder'

module ClaimsApi
  class VANotifyFollowUpJob < ClaimsApi::ServiceBase
    sidekiq_options retry: 14

    LOG_TAG = 'va_notify_follow_up_job'
    NON_RETRY_STATUSES = %w[cancelled delivered failed permanent-failure validation-failed].freeze
    RETRY_STATUSES = %w[created pending sending sent temporary-failure].freeze
    NOTIFY_STATUS_DICTIONARY = {
      IN_PROGRESS: %w[created pending sending sent temporary-failure],
      SUCCESS: ['delivered'],
      FAILED: %w[cancelled failed permanent-failure validation-failed]
    }.freeze
    RETRY_ATTEMPT_MAX = 48 # ~ 24 hours @ 30 min intervals

    sidekiq_retries_exhausted do |message|
      msg = "Retries exhausted. #{message['error_message']}"
      slack_client = SlackNotify::Client.new(webhook_url: Settings.claims_api.slack.webhook_url,
                                             channel: '#api-benefits-claims-alerts',
                                             username: 'Failed ClaimsApi::VANotifyFollowUpJob')
      slack_client.notify(msg)
    end

    # requeues every 30 minutes for up to 24 hours (max 48 requeues) for retryable statuses
    def perform(notification_id, poa_id = nil, attempt = 0)
      status = notification_response_status(notification_id)
      message = "Status for notification #{notification_id} was '#{status}'"
      message += ". POA ID: #{poa_id}" if poa_id
      # log the status of the notification
      update_poa_process_step(poa_id, status) if poa_id
      # if the status is a permanent failure, handle it (log and alert)
      handle_failure(message) if status == 'permanent-failure'
      # if the status is not an explicit non-retryable status, requeue the job to check again in 30 minutes
      # (handles nil status as well)
      requeue_job(notification_id, poa_id, message, attempt) unless NON_RETRY_STATUSES.include?(status)
    rescue => e
      ClaimsApi::Logger.log(
        'va_follow_up_job',
        message: "Failed to check: #{get_error_message(e)}"
      )
      raise e
    end

    private

    def update_poa_process_step(poa_id, status)
      # Call logic to map VANotify status to our internal step status
      step_status = map_notify_status(status)
      # Update the POA process step with latest status
      poa = ClaimsApi::PowerOfAttorney.find(poa_id)
      process = ClaimsApi::Process.find_or_create_by(processable: poa, step_type: 'CLAIMANT_NOTIFICATION')
      if step_status == 'IN_PROGRESS'
        process.update!(step_status:, error_messages: [])
      else
        process.update!(step_status:, error_messages: [], completed_at: Time.zone.now)
      end
    end

    def requeue_job(notification_id, poa_id, message, attempt)
      if attempt < RETRY_ATTEMPT_MAX # ~ 24 hours @ 30 min intervals
        ClaimsApi::Logger.log(
          'va_follow_up_job',
          message: "Re-enqueueing job for notification #{notification_id}. Attempt: #{attempt + 1}. #{message}"
        )
        # Re-enqueue the job to check again in 30 minutes and increment the attempt count
        self.class.perform_in(30.minutes, notification_id, poa_id, attempt + 1)
      else
        ClaimsApi::Logger.log(
          'va_follow_up_job',
          message: "Max attempts reached for notification #{notification_id}. #{message}"
        )
        complete_stalled_process(poa_id) if poa_id
        alert_max_attempts_reached(message)
      end
    end

    def complete_stalled_process(poa_id)
      poa = ClaimsApi::PowerOfAttorney.find(poa_id)
      process = ClaimsApi::Process.find_by(processable: poa, step_type: 'CLAIMANT_NOTIFICATION')
      process&.update!(
        step_status: 'FAILED', error_messages: ['Max polling attempts reached'], completed_at: Time.zone.now
      )
    end

    def alert_max_attempts_reached(message)
      # validate the webhook URL is present before sending the alert
      webhook_url = Settings.claims_api.slack.webhook_url.to_s
      return if webhook_url.blank?

      msg = "Max polling attempts reached (#{RETRY_ATTEMPT_MAX}). Notification may be permanently stuck. #{message}"
      slack_client = SlackNotify::Client.new(webhook_url:,
                                             channel: '#api-benefits-claims-alerts',
                                             username: 'Failed ClaimsApi::VANotifyFollowUpJob')
      slack_client.notify(msg)
    end

    def handle_failure(message)
      ClaimsApi::Logger.log(LOG_TAG, message:)
      slack_alert_on_failure(self.class.name, message)
    end

    def notification_response_status(notification_id)
      res = client.get(notification_id.to_s)&.body
      res[:status]
    end

    def map_notify_status(vanotify_status)
      status = ''
      NOTIFY_STATUS_DICTIONARY.each do |key, value|
        status = key.to_s if value.include?(vanotify_status.to_s)
      end
      raise StandardError, "Unknown VANotify status: #{vanotify_status}" if status.blank?

      status
    end

    def client
      base_name = Settings.vanotify.client_url || 'https://staging-api.va.gov'

      @token ||= generate_jwt_token
      raise StandardError, 'VA Notify token missing' if @token.nil?

      Faraday.new("#{base_name}/v2/notifications/",
                  headers: { 'Authorization' => "Bearer #{@token}" }) do |f|
        f.response :raise_custom_error
        f.response :json, parser_options: { symbolize_names: true }
        f.adapter Faraday.default_adapter
      end
    end

    def generate_jwt_token
      client_secret = settings.notification_client_secret
      service_id = settings.notify_service_id
      alg = 'HS256'

      ClaimsApi::JwtEncoder.new.encode_va_notify_jwt(alg, service_id, client_secret)
    end

    def settings
      if Flipper.enabled?(:claims_api_vanotify_service_migration)
        Settings.vanotify.services.lighthouse_benefits_claims
      else
        Settings.claims_api.vanotify.services.lighthouse
      end
    end
  end
end
