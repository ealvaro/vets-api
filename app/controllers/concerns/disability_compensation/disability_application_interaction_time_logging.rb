# frozen_string_literal: true

module DisabilityCompensation
  module DisabilityApplicationInteractionTimeLogging
    ACTIVE_IDLE_GAP_SECONDS = 10.minutes.to_i
    LAST_SESSION_ACTIVITY_AT_METADATA_KEY = 'lastSessionActivityAt'

    private

    def active_delta_seconds(previous_activity_at, occurred_at)
      return nil if previous_activity_at.blank?

      delta = occurred_at - previous_activity_at
      delta.negative? ? nil : delta.round
    end

    def read_last_session_activity_at(in_progress_form)
      raw_value = in_progress_form_raw_metadata(in_progress_form)&.dig(LAST_SESSION_ACTIVITY_AT_METADATA_KEY)
      return nil if raw_value.blank?

      Time.zone.parse(raw_value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def persist_last_session_activity_at!(in_progress_form, occurred_at: Time.current)
      return if in_progress_form.blank?

      metadata = (in_progress_form_raw_metadata(in_progress_form) || {}).deep_dup
      metadata[LAST_SESSION_ACTIVITY_AT_METADATA_KEY] = occurred_at.utc.iso8601(3)

      # rubocop:disable Rails/SkipsModelValidations
      # update_columns is used intentionally: update! would bump updated_at, which surfaces
      # as metadata['lastUpdated'], making a read-only "show" look like a form edit -
      # which we want to avoid.
      in_progress_form.update_columns(metadata:)
      # rubocop:enable Rails/SkipsModelValidations
    rescue => e
      Rails.logger.warn('Form526 IPF lastSessionActivityAt persistence failed', exception: e)
    end

    def in_progress_form_raw_metadata(in_progress_form)
      return nil if in_progress_form.blank?

      return in_progress_form[:metadata] if in_progress_form.respond_to?(:[])

      in_progress_form.metadata
    end

    def log_ipf_active_time_event(event_type:, in_progress_form_id:, terminal:, context: {})
      occurred_at = Time.current
      delta_seconds = active_delta_seconds(context[:previous_activity_at], occurred_at)

      Rails.logger.info(
        'Form526 interaction',
        event_type:,
        occurred_at: occurred_at.utc.iso8601(3),
        request_id: request.request_id,
        controller: self.class.name,
        action: action_name,
        form_id: FormProfiles::VA526ez::FORM_ID,
        in_progress_form_id:,
        submission_id: context[:submission_id],
        user_uuid: @current_user&.uuid,
        terminal:,
        active_delta_seconds: delta_seconds,
        active_idle_gap_exceeded: delta_seconds && (delta_seconds >= ACTIVE_IDLE_GAP_SECONDS || nil)
      )
    end
  end
end
