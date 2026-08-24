# frozen_string_literal: true

require 'sidekiq'

module VANotify
  class InProgressForms
    include Sidekiq::Job

    SPREAD_WINDOW = 1.hour

    def perform
      ids = FindInProgressForms.new.to_notify
      return if ids.empty?

      if Flipper.enabled?(:va_notify_in_progress_forms_stagger)
        # Stagger enqueues across SPREAD_WINDOW so the daily run trickles jobs into Sidekiq,
        # instead of bursting all at once.
        step = SPREAD_WINDOW.to_f / ids.size
        ids.each_with_index do |in_progress_form_id, index|
          InProgressFormReminder.perform_in((step * index).seconds, in_progress_form_id)
        end
      else
        ids.each do |in_progress_form_id|
          InProgressFormReminder.perform_async(in_progress_form_id)
        end
      end
    end
  end
end
