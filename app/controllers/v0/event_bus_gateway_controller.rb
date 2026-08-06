# frozen_string_literal: true

module V0
  class EventBusGatewayController < ::SignIn::ServiceAccountApplicationController
    service_tag 'event_bus_gateway'

    def self.deployment_environment
      env = Settings.vsp_environment || Rails.env.to_s
      %w[development test staging production].include?(env) ? env : 'blank'
    end

    def self.load_templates
      YAML.safe_load_file(
        Rails.root.join('config', 'event_bus_gateway', 'templates.yml')
      )[deployment_environment]
    rescue Errno::ENOENT, Psych::BadAlias => e
      Rails.logger.warn("EventBusGatewayController: Failed to load templates.yml: #{e.message}")
      {}
    end

    TEMPLATES = load_templates.freeze

    REQUIRED_EMAIL_TEMPLATES = %w[
      default_template
      mobile_link_template
      pension_claims_template
      pension_mobile_link_template
    ].freeze

    def self.missing_required_templates
      email_templates = TEMPLATES['email']
      return REQUIRED_EMAIL_TEMPLATES.dup if email_templates.nil?

      missing = []
      REQUIRED_EMAIL_TEMPLATES.each do |template_key|
        missing << template_key if email_templates[template_key].blank?
      end
      missing
    end

    def self.validate_templates
      missing_required_templates.empty?
    end

    TEMPLATES_VALID = validate_templates.freeze

    def send_email
      EventBusGateway::LetterReadyEmailJob.perform_async(
        participant_id,
        select_email_template(send_email_params.require(:template_id))
      )
      head :ok
    end

    def send_push
      EventBusGateway::LetterReadyPushJob.perform_async(
        participant_id,
        send_push_params.require(:template_id)
      )
      head :ok
    end

    def send_sms
      EventBusGateway::LetterReadySmsJob.perform_async(
        participant_id,
        send_sms_params.require(:template_id)
      )
      head :ok
    end

    def send_notifications
      validate_at_least_one_template!
      return if performed?

      EventBusGateway::LetterReadyNotificationJob.perform_async(
        participant_id,
        {
          'email' => select_email_template(send_notifications_params[:email_template_id]),
          'push' => send_notifications_params[:push_template_id],
          'sms' => send_notifications_params[:sms_template_id]
        }
      )
      head :ok
    end

    private

    def participant_id
      @participant_id ||= @service_account_access_token.user_attributes['participant_id']
    end

    def send_email_params
      params.permit(:template_id)
    end

    def send_push_params
      params.permit(:template_id)
    end

    def send_sms_params
      params.permit(:template_id)
    end

    def send_notifications_params
      params.permit(:email_template_id, :push_template_id, :sms_template_id)
    end

    def validate_at_least_one_template!
      return if send_notifications_params[:email_template_id].present? ||
                send_notifications_params[:push_template_id].present? ||
                send_notifications_params[:sms_template_id].present?

      render json: {
        errors: [{
          title: 'Bad Request',
          detail: 'At least one of email_template_id, push_template_id, or sms_template_id is required',
          status: '400'
        }]
      }, status: :bad_request
    end

    def select_email_template(original_template)
      if original_template.blank?
        log_blank_template
        return original_template
      end

      unless TEMPLATES_VALID
        log_invalid_templates
        log_required_templates
        return original_template
      end

      unless universal_link_enabled?
        log_universal_link_disabled
        return original_template
      end

      match_and_swap_template(original_template)
    end

    def match_and_swap_template(original_template)
      case original_template
      when TEMPLATES['email']['default_template']
        log_default_template_matched
        swap_to_mobile_template('mobile_link_template', 'universal link')
      when TEMPLATES['email']['pension_claims_template']
        log_pension_template_matched
        swap_to_mobile_template('pension_mobile_link_template', 'pension mobile link')
      else
        log_no_template_matched(original_template)
        original_template
      end
    end

    def swap_to_mobile_template(template_key, description)
      template_id = TEMPLATES['email'][template_key]

      log_template_swap(description, template_id)

      template_id
    end

    def universal_link_enabled?
      if participant_id.blank?
        log_blank_participant_id
        return false
      end

      Flipper.enabled?(:event_bus_gateway_letter_ready_email_universal_link, Flipper::Actor.new(participant_id))
    end

    def log_blank_template
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info('EventBusGatewayController: original_template is blank')
    end

    def log_universal_link_disabled
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info('EventBusGatewayController: universal_link feature flag is disabled')
    end

    def log_blank_participant_id
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info(
        'EventBusGatewayController: participant_id is blank; universal_link feature will not be evaluated'
      )
    end

    def log_invalid_templates
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info('EventBusGatewayController: templates are invalid')
    end

    def log_default_template_matched
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info('EventBusGatewayController: matched default email template')
    end

    def log_pension_template_matched
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info('EventBusGatewayController: matched pension email template')
    end

    def log_no_template_matched(original_template)
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info(
        'EventBusGatewayController: no template case matched',
        { template_id: original_template }
      )
    end

    def log_template_swap(description, template_id)
      return unless Flipper.enabled?(:event_bus_gateway_controller_visibility)

      Rails.logger.info(
        "EventBusGatewayController using #{description} template",
        { swapped_template: template_id }
      )
    end

    def log_required_templates
      return unless Flipper.enabled?(:event_bus_gateway_controller_validation_visibility)

      missing = self.class.missing_required_templates
      return if missing.empty?

      Rails.logger.info(
        'EventBusGatewayController: missing required templates',
        { missing_templates: missing }
      )
    end
  end
end
