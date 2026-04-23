# frozen_string_literal: true

require 'dgi/forms/service/sponsor_service'
require 'dgi/forms/service/claimant_service'
require 'dgi/forms/service/submission_service'
require 'dgi/forms/service/letter_service'

module MebApi
  module V0
    class FormsController < MebApi::V0::BaseController
      before_action :set_type, only: %i[claim_letter claim_status claimant_info]

      # Default form type constants (used when form_type param is not provided)
      FORM_TYPE = MebApi::ConfirmationEmailConfig::FORM_1990EMEB
      FORM_TAG = MebApi::ConfirmationEmailConfig::TAG_1990EMEB
      FLIPPER_KEY = :form1990emeb_confirmation_email

      # Form-type-aware configuration for confirmation emails
      CONFIRMATION_EMAIL_CONFIG = {
        '10297' => {
          worker: MebApi::V0::Submit10297FormConfirmation,
          form_tag: MebApi::ConfirmationEmailConfig::TAG_10297,
          flipper_key: :form10297_meb_confirmation_email
        },
        '225490' => {
          worker: MebApi::V0::Submit225490FormConfirmation,
          form_tag: MebApi::ConfirmationEmailConfig::TAG_225490,
          flipper_key: :meb5490_automation
        }
      }.freeze

      def claim_letter
        claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = claimant_response.claimant_id
        claim_status_response = claim_status_service.get_claim_status(params, claimant_id, @form_type)
        claim_letter_response = letter_service.get_claim_letter(claimant_id, @form_type)
        is_eligible = claim_status_response.claim_status == 'ELIGIBLE'

        response = if valid_claimant_response?(claimant_response)
                     claim_letter_response
                   else
                     claimant_response
                   end

        date = Time.now.getlocal
        timestamp = date.strftime('%m/%d/%Y %I:%M:%S %p')
        filename = is_eligible ? "Post-9/11 GI_Bill_CoE_#{timestamp}" : "Post-9/11 GI_Bill_Denial_#{timestamp}"

        send_data response.body, filename: "#{filename}.pdf", type: 'application/pdf', disposition: 'attachment'

        nil
      end

      def claim_status
        forms_claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = forms_claimant_response.claimant_id

        if claimant_id.present?
          claim_status_response = claim_status_service.get_claim_status(params, claimant_id, @form_type)
          response = valid_claimant_response?(forms_claimant_response) ? claim_status_response : forms_claimant_response
          srlzr = valid_claimant_response?(forms_claimant_response) ? ClaimStatusSerializer : ToeClaimantInfoSerializer

          render json: srlzr.new(response)
        else
          render json: { data: { attributes: { claimStatus: 'INPROGRESS' } } }, status: :ok
        end
      end

      def claimant_info
        response = form_claimant_service.get_claimant_info(@form_type)

        render json: ToeClaimantInfoSerializer.new(response)
      end

      def sponsors
        response = sponsor_service.post_sponsor

        render json: SponsorsSerializer.new(response)
      end

      def submit_claim
        StatsD.increment('api.meb.submit_claim.attempt')
        response_data = fetch_direct_deposit_info
        response = submission_service.submit_claim(params, response_data)

        clear_saved_form(params[:form_id]) if params[:form_id]

        render json: {
          data: {
            status: response.status
          }
        }
      rescue => e
        log_submission_error(e, 'MEB Forms submit_claim failed')
        raise
      end

      def send_confirmation_email
        config = resolve_email_config
        log_confirmation_email_request(config[:form_tag], config[:flipper_key])

        unless Flipper.enabled?(config[:flipper_key])
          log_confirmation_email_skipped(config[:form_tag], 'flipper_disabled')
          return head :no_content
        end

        attrs = validate_confirmation_email_attributes(config[:form_tag])
        return head :unprocessable_entity unless attrs

        dispatch_confirmation_email(attrs[:email], config)
      end

      private

      def set_type
        @form_type = case params['type']
                     when 'ToeSubmission' then 'toe'
                     when 'Chapter35Submission' then 'Chapter35'
                     else params['type']&.capitalize
                     end
      end

      def resolve_email_config
        CONFIRMATION_EMAIL_CONFIG.fetch(params[:form_type].to_s, {
                                          worker: MebApi::V0::Submit1990emebFormConfirmation,
                                          form_tag: FORM_TAG,
                                          flipper_key: FLIPPER_KEY
                                        })
      end

      def dispatch_confirmation_email(email, config)
        config[:worker].perform_async(
          params[:claim_status],
          email,
          params[:first_name]&.upcase || @current_user.first_name&.upcase,
          @current_user.icn
        )
        log_confirmation_email_dispatched(config[:form_tag], params[:claim_status])
      end

      def valid_claimant_response?(response)
        [200, 201, 204].include?(response.status)
      end

      def render_claimant_error(response)
        render json: {
          errors: [{
            title: 'Claimant information error',
            detail: 'Unable to retrieve claimant information',
            code: response.status.to_s,
            status: response.status.to_s
          }]
        }, status: response.status
      end

      def determine_response_and_serializer(claim_status_response, claimant_response)
        if claim_status_response.status == valid_claimant_response?(claimant_response)
          [claim_status_response, ClaimStatusSerializer]
        else
          [claimant_response, ToeClaimantInfoSerializer]
        end
      end

      def form_claimant_service
        MebApi::DGI::Forms::Claimant::Service.new(@current_user)
      end

      def letter_service
        MebApi::DGI::Forms::Letters::Service.new(@current_user)
      end

      def sponsor_service
        MebApi::DGI::Forms::Sponsor::Service.new(@current_user)
      end

      def submission_service
        MebApi::DGI::Forms::Submission::Service.new(@current_user)
      end

      # Fetch unmasked direct deposit if asterisks present. Gracefully handles failures.
      def fetch_direct_deposit_info
        return nil if Rails.env.development?

        account_number = params.dig(:form, :direct_deposit, :direct_deposit_account_number)
        routing_number = params.dig(:form, :direct_deposit, :direct_deposit_routing_number)
        return nil unless account_number&.include?('*') || routing_number&.include?('*')

        DirectDeposit::Client.new(@current_user&.icn).get_payment_info.tap do |response_data|
          if response_data.nil?
            Rails.logger.warn('DirectDeposit::Client returned nil response, proceeding without direct deposit info')
          end
        end
      rescue => e
        Rails.logger.error("Lighthouse direct deposit service error: #{e}")
        nil
      end
    end
  end
end
