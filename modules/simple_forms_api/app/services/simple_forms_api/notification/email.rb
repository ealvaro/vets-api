# frozen_string_literal: true

module SimpleFormsApi
  module Notification
    class Email
      attr_reader :form_number, :confirmation_number, :date_submitted, :expiration_date, :lighthouse_updated_at,
                  :notification_type, :user, :user_account, :form_data, :form

      TEMPLATE_IDS = YAML.load_file(
        'modules/simple_forms_api/app/services/simple_forms_api/notification/template_ids.yml'
      )
      SUPPORTED_FORMS = TEMPLATE_IDS.keys

      def initialize(config, notification_type: :confirmation, user: nil, user_account: nil)
        @notification_type = notification_type

        check_missing_keys(config)
        check_if_form_is_supported(config)

        @form_data = config[:form_data]
        @form_number = config[:form_number]
        @confirmation_number = config[:confirmation_number]
        @date_submitted = config[:date_submitted]
        @expiration_date = config[:expiration_date]
        @lighthouse_updated_at = config[:lighthouse_updated_at]
        @form = "SimpleFormsApi::#{cleaned_form_number}".constantize.new(form_data)
        @user = user
        @user_account = user_account
      end

      def send(at: nil)
        return unless flipper?
        return unless template_id

        scheduled_at = at
        email_job_id = if scheduled_at
                         enqueue_email(scheduled_at, template_id)
                       else
                         send_email_now(template_id)
                       end

        if email_job_id
          Rails.logger.info('Simple Forms - Email job enqueued', email_job_id:, confirmation_number:)
        elsif error_notification?
          StatsD.increment('silent_failure', tags: statsd_tags)
          Rails.logger.error('Simple Forms - Error email job failed to enqueue', confirmation_number:)
        else
          Rails.logger.error('Simple Forms - Non-error email job failed to enqueue', confirmation_number:)
        end
      end

      private

      def vanotify_api_key
        api_key = Settings.vanotify.services.va_gov.api_key.to_s
        raise 'VANotify API key not configured' if api_key.blank?

        api_key
      end

      def check_missing_keys(config)
        all_keys = %i[form_data form_number date_submitted]
        all_keys << :confirmation_number if needs_confirmation_number?
        all_keys << :expiration_date if config[:form_number] == 'vba_21_0966_intent_api'

        missing_keys = all_keys.select { |key| config[key].nil? || config[key].to_s.strip.empty? }

        if missing_keys.any?
          StatsD.increment('silent_failure', tags: statsd_tags) if error_notification?
          raise ArgumentError, "Missing keys: #{missing_keys.join(', ')}"
        end
      end

      def check_if_form_is_supported(config)
        unless SUPPORTED_FORMS.include?(config[:form_number])
          StatsD.increment('silent_failure', tags: statsd_tags) if error_notification?
          raise ArgumentError, "Unsupported form: given form number was #{config[:form_number]}"
        end
      end

      def cleaned_form_number
        # We need this annoying cleaned_form_number for now because 21-0966 has an intent_api variant
        # vba_21_0966_intent_api becomes vba_21_0966
        form_number.gsub('_intent_api', '').titleize.gsub(' ', '')
      end

      def flipper?
        number = form_number
        number = 'vba_21_0966' if form_number.start_with? 'vba_21_0966'

        base = number.gsub('vba_', '')

        if base == '40_1330m'
          return Flipper.enabled?(:form40_1330m_expiration_email) if notification_type.to_s == 'expiration'

          return Flipper.enabled?(:form40_1330m_confirmation_email)
        end

        Flipper.enabled?(:"form#{base}_confirmation_email")
      end

      def template_id
        template_id_suffix = TEMPLATE_IDS[form_number][notification_type.to_s]
        if form.should_send_to_point_of_contact?
          template_id_suffix = TEMPLATE_IDS['vba_20_10207']['point_of_contact_error']
        end
        @_template_id ||= Settings.vanotify.services.va_gov.template_id[template_id_suffix]
      end

      def enqueue_email(at, template_id)
        email_from_form_data = resolve_notification_email

        # async job and form data includes email
        if email_from_form_data
          async_job_with_form_data(email_from_form_data, at, template_id)
        # async job and we have a UserAccount
        elsif user_account
          async_job_with_user_account(user_account, at, template_id)
        end
      end

      def async_job_with_form_data(email, at, template_id)
        if Flipper.enabled?(:va_notify_v2_simple_forms_email)
          callback_options = email_args.last
          VANotify::V2::QueueEmailJob.enqueue_at(
            at,
            email,
            template_id,
            get_personalization,
            'Settings.vanotify.services.va_gov.api_key',
            callback_options
          )
        else
          VANotify::EmailJob.perform_at(
            at,
            email,
            template_id,
            get_personalization,
            *email_args
          )
        end
      end

      def async_job_with_user_account(user_account, at, template_id)
        first_name_from_user_account = get_first_name_from_user_account
        personalization = get_personalization
        personalization.merge!('first_name' => first_name_from_user_account) if first_name_from_user_account

        if Flipper.enabled?(:va_notify_v2_simple_forms_user_account_email)
          VANotify::V2::QueueUserAccountJob.enqueue_at(
            at, user_account.id, template_id, personalization,
            'Settings.vanotify.services.va_gov.api_key', email_args.last
          )
        else
          VANotify::UserAccountJob.perform_at(at, user_account.id, template_id, personalization, *email_args)
        end
      end

      def send_email_now(template_id)
        email_address = resolve_notification_email || user&.email
        personalization = get_personalization
        return unless email_address && personalization

        if Flipper.enabled?(:va_notify_v2_simple_forms_email)
          callback_options = email_args.last
          VANotify::V2::QueueEmailJob.enqueue(
            email_address,
            template_id,
            personalization,
            'Settings.vanotify.services.va_gov.api_key',
            callback_options
          )
        else
          VANotify::EmailJob.perform_async(
            email_address,
            template_id,
            personalization,
            *email_args
          )
        end
      end

      def get_personalization
        config = { date_submitted:, confirmation_number:, lighthouse_updated_at: }
        personalization = SimpleFormsApi::Notification::Personalization.new(form:, config:, expiration_date:)
        result = personalization.to_hash

        # Override first_name for notification-type-specific first name (e.g., cemetery contact),
        # but only when a non-blank value is provided so we don't erase an existing first_name.
        type_specific_first_name_method = :"#{notification_type}_first_name"
        if result && form.respond_to?(type_specific_first_name_method)
          type_specific_first_name = form.public_send(type_specific_first_name_method)
          result['first_name'] = type_specific_first_name.titleize if type_specific_first_name.present?
        end

        result
      end

      # Resolves the email address to send to based on the notification type.
      # If the form model defines a type-specific email method (e.g., `cemetery_notification_email_address`),
      # that method is used; otherwise, falls back to the default `notification_email_address`.
      def resolve_notification_email
        type_specific_method = :"#{notification_type}_email_address"
        if form.respond_to?(type_specific_method)
          form.public_send(type_specific_method).presence
        else
          form.notification_email_address.presence
        end
      end

      def get_first_name_from_user_account
        mpi_response = MPI::Service.new.find_profile_by_identifier(identifier_type: 'ICN', identifier: user_account.icn)
        if mpi_response
          error = mpi_response.error
          Rails.logger.error('MPI response error', { error: }) if error

          first_name = mpi_response.profile&.given_names&.first
          Rails.logger.error('MPI profile missing first_name') unless first_name

          first_name
        end
      end

      def email_args
        options = {
          callback_metadata: {
            notification_type: notification_type.to_s,
            form_number:,
            confirmation_number:,
            statsd_tags:
          }
        }

        if Flipper.enabled?(:simple_forms_email_delivery_callback)
          options[:callback_klass] = 'SimpleFormsApi::Notification::EmailDeliveryStatusCallback'
        end

        [
          vanotify_api_key, options
        ]
      end

      def statsd_tags
        { 'service' => 'veteran-facing-forms', 'function' => "#{form_number} form submission to Lighthouse" }
      end

      def error_notification?
        notification_type == :error
      end

      def needs_confirmation_number?
        # All email templates require confirmation_number except :duplicate for 26-4555 (SAHSHA)
        # Only 26-4555 supports the :duplicate notification_type
        notification_type != :duplicate
      end
    end
  end
end
