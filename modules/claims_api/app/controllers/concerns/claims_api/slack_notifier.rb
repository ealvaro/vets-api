# frozen_string_literal: true

module ClaimsApi
  module SlackNotifier
    extend ActiveSupport::Concern

    private

    def request_slack_alert(source, message)
      webhook_url = Settings.claims_api.slack.webhook_url.to_s
      return if webhook_url.blank?

      slack_client = SlackNotify::Client.new(webhook_url:,
                                             channel: '#api-benefits-claims-alerts',
                                             username: "Failed #{source}")
      slack_client.notify(message)
    rescue => e
      ClaimsApi::Logger.log('request_slack_alert',
                            level: :error,
                            message: "Failed to send Slack alert: #{e.message}")
    end
  end
end
