# frozen_string_literal: true

module IvcChampva
  class Email
    attr_reader :data

    EMAIL_TEMPLATE_MAP = {
      '10-10D' => Settings.vanotify.services.ivc_champva.template_id.form_10_10d_email,
      '10-10D-EXTENDED' => Settings.vanotify.services.ivc_champva.template_id.form_10_10d_email,
      '10-10D-SUPPLEMENTAL' =>
        Settings.vanotify.services.ivc_champva.template_id.form_10_10d_supplemental_existing_email,
      '10-10D-SUPPLEMENTAL-EXISTING' =>
        Settings.vanotify.services.ivc_champva.template_id.form_10_10d_supplemental_existing_email,
      '10-10D-SUPPLEMENTAL-ENROLLMENT' =>
        Settings.vanotify.services.ivc_champva.template_id.form_10_10d_supplemental_enrollment_email,
      '10-10D-FAILURE' => Settings.vanotify.services.ivc_champva.template_id.form_10_10d_failure_email,
      '10-10D-EXTENDED-FAILURE' => Settings.vanotify.services.ivc_champva.template_id.form_10_10d_failure_email,
      '10-10D-SUPPLEMENTAL-FAILURE' =>
        Settings.vanotify.services.ivc_champva.template_id.form_10_10d_supplemental_existing_failure_email,
      '10-10D-SUPPLEMENTAL-EXISTING-FAILURE' =>
        Settings.vanotify.services.ivc_champva.template_id.form_10_10d_supplemental_existing_failure_email,
      '10-10D-SUPPLEMENTAL-ENROLLMENT-FAILURE' =>
        Settings.vanotify.services.ivc_champva.template_id.form_10_10d_supplemental_enrollment_failure_email,
      '10-7959F-1' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959f_1_email,
      '10-7959F-1-FAILURE' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959f_1_failure_email,
      '10-7959F-2' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959f_2_email,
      '10-7959F-2-FAILURE' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959f_2_failure_email,
      '10-7959C' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959c_email,
      '10-7959C-FAILURE' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959c_failure_email,
      '10-7959A' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959a_email,
      '10-7959A-FAILURE' => Settings.vanotify.services.ivc_champva.template_id.form_10_7959a_failure_email,
      'PEGA-TEAM_MISSING_STATUS' => Settings.vanotify.services.ivc_champva.template_id.pega_team_missing_status_email,
      'PEGA-TEAM-ZSF' => Settings.vanotify.services.ivc_champva.template_id.pega_team_zsf_email
    }.freeze

    def initialize(data, sync: false)
      @data = data
      @sync = sync
    end

    def send_email
      return false unless valid_environment?

      template_id = resolve_template_id
      return false unless template_id

      # Create a subset of `data` - Using .index_with rather than .slice so that keys
      # default to `nil` if not present in `data`. This helps us w/ testing.
      personalisation = %i[first_name last_name file_count pega_status date_submitted form_uuid]
                        .index_with { |k| data[k] }

      # If no callback_klass is provided, should fail safely per va_notify implementation.
      # See: https://github.com/department-of-veterans-affairs/vets-api/tree/master/modules/va_notify#how-teams-can-integrate-with-callbacks
      callback_options = { callback_klass: data[:callback_klass], callback_metadata: data[:callback_metadata] }

      if @sync
        perform_email_send_sync(template_id, personalisation, callback_options)
      else
        perform_email_send(template_id, personalisation, callback_options)
      end

      Rails.logger.info "Pega Status Update Email: #{data[:file_count].to_i} file(s)"

      true
    rescue => e
      Rails.logger.error "Pega Status Update Email Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    private

    def resolve_template_id
      template_id = EMAIL_TEMPLATE_MAP[data[:template_id]] || EMAIL_TEMPLATE_MAP[data[:form_number]]
      return template_id if template_id

      Rails.logger.warn(
        'IvcChampva::Email: missing or unmapped key, unable to send email',
        template_id: data[:template_id],
        form_number: data[:form_number]
      )
      nil
    end

    def perform_email_send(template_id, personalisation, callback_options)
      VANotify::V2::QueueEmailJob.enqueue(
        data[:email],
        template_id,
        personalisation,
        'Settings.vanotify.services.ivc_champva.api_key',
        callback_options
      )
    end

    def perform_email_send_sync(template_id, personalisation, callback_options)
      api_key = Settings.vanotify.services.ivc_champva.api_key
      VaNotify::Service.new(api_key, callback_options).send_email(
        email_address: data[:email],
        template_id:,
        personalisation:
      )
    end

    def valid_environment?
      %w[production staging].include?(Rails.env)
    end
  end
end
