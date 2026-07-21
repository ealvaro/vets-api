# frozen_string_literal: true

module IvcChampva
  # General purpose callback class used for when we send emails to users.
  # This is used so we can maintain email numbers in DD.
  #
  # Modified from https://va.ghe.com/software/vets-api/tree/master/modules/va_notify#how-teams-can-integrate-with-callbacks
  #

  class EmailNotificationCallback
    def self.call(notification)
      # @param ac [hash] contains properties form_id, form_uuid, and notification_type
      # as defined under callback_metadata.additional_context when the email was sent
      #   (e.g.: {form_id: '10-10d', form_uuid: '12345678-1234-5678-1234-567812345678',
      #   notification_type: 'confirmation'})
      ac = notification.callback_metadata['additional_context']

      # This is the actual contribution we care about:
      monitor.track_email_sent(ac['form_id'], ac['form_uuid'], notification.status, ac['notification_type'])

      case notification.status
      when 'delivered'
        # success
        StatsD.increment('api.vanotify.notifications.delivered')
        monitor.log_silent_failure_avoided(ac)
      when 'permanent-failure'
        # delivery failed
        StatsD.increment('api.vanotify.notifications.permanent_failure')
        Rails.logger.error(notification_id: notification.notification_id, source: notification.source_location,
                           status: notification.status, status_reason: notification.status_reason)
        # No confirmation reached the applicant - feed the ZSF alerting/dashboard pipeline
        monitor.log_silent_failure(ac)
      when 'temporary-failure'
        # the api will continue attempting to deliver - success is still possible
        StatsD.increment('api.vanotify.notifications.temporary_failure')
        Rails.logger.error(notification_id: notification.notification_id, source: notification.source_location,
                           status: notification.status, status_reason: notification.status_reason)
      else
        StatsD.increment('api.vanotify.notifications.other')
        Rails.logger.error(notification_id: notification.notification_id, source: notification.source_location,
                           status: notification.status, status_reason: notification.status_reason)
      end
    end

    ##
    # retreive a monitor for tracking
    #
    # @return [IvcChampva::Monitor]
    #
    def self.monitor
      IvcChampva::Monitor.new
    end
  end
end
