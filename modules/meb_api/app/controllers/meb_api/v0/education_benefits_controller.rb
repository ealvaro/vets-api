# frozen_string_literal: true

require 'dgi/claimant/service'
require 'dgi/letters/service'
require 'dgi/status/service'
require 'dgi/eligibility/service'
require 'dgi/automation/service'
require 'dgi/submission/service'
require 'dgi/enrollment/service'
require 'dgi/contact_info/service'
require 'dgi/exclusion_period/service'

module MebApi
  module V0
    class EducationBenefitsController < MebApi::V0::BaseController
      before_action :set_type, only: %i[claim_letter claim_status claimant_info eligibility]

      # Default form type constants (used when chapter type is not 1606/30)
      FORM_TYPE = MebApi::ConfirmationEmailConfig::FORM_1990MEB
      FORM_TAG = MebApi::ConfirmationEmailConfig::TAG_1990MEB
      FLIPPER_KEY = :form1990meb_confirmation_email

      # Benefit type to filename prefix mapping for claim letters
      # This controller handles: Chapter 33, Chapter 1606, Chapter 30 (1990), and VetTec
      BENEFIT_TYPE_FILENAME_MAPPING = {
        'VetTec' => 'VT2',
        'Chapter1606' => 'CH1606',
        'Chapter30' => 'CH30'
        # Add more benefit types here as needed:
        # 'Chapter33' => 'CH33'
      }.freeze

      # Chapter-type-aware configuration for confirmation emails
      CONFIRMATION_EMAIL_CONFIG = {
        'chapter1606' => {
          worker: MebApi::V0::Submit1606FormConfirmation,
          form_tag: MebApi::ConfirmationEmailConfig::TAG_1990_CHAPTER1606
        },
        'chapter30' => {
          worker: MebApi::V0::Submit30FormConfirmation,
          form_tag: MebApi::ConfirmationEmailConfig::TAG_1990_CHAPTER30
        }
      }.freeze

      def claimant_info
        response = automation_service.get_claimant_info(@form_type)

        render json: AutomationSerializer.new(response)
      end

      def eligibility
        claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = claimant_response.claimant_id

        eligibility_response = eligibility_service.get_eligibility(claimant_id)

        response = claimant_response.status == 201 ? eligibility_response : claimant_response
        serializer = claimant_response.status == 201 ? EligibilitySerializer : ClaimantSerializer

        render json: serializer.new(response)
      end

      def claim_status
        claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = claimant_response.claimant_id

        claim_status_response = claim_status_service.get_claim_status(params, claimant_id, @form_type)

        response = claimant_response.status == 201 ? claim_status_response : claimant_response
        serializer = claimant_response.status == 201 ? ClaimStatusSerializer : ClaimantSerializer

        render json: serializer.new(response)
      end

      def claim_letter
        claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = claimant_response.claimant_id
        claim_status_response = claim_status_service.get_claim_status(params, claimant_id, @form_type)
        claim_letter_response = claim_letters_service.get_claim_letter(claimant_id, @form_type)
        is_eligible = claim_status_response.claim_status == 'ELIGIBLE'
        response = claimant_response.status == 201 ? claim_letter_response : claimant_response

        date = Time.now.getlocal
        timestamp = date.strftime('%m/%d/%Y %I:%M:%S %p')

        filename = if Flipper.enabled?(:meb_dynamic_letter_filename)
                     generate_dynamic_filename(@form_type, is_eligible, timestamp)
                   else
                     is_eligible ? "Post-9/11 GI_Bill_CoE_#{timestamp}" : "Post-9/11 GI_Bill_Denial_#{timestamp}"
                   end

        send_data response.body, filename: "#{filename}.pdf", type: 'application/pdf', disposition: 'attachment'

        nil
      end

      def submit_claim
        StatsD.increment('api.meb.submit_claim.attempt')
        response_data = fetch_direct_deposit_info
        response = submission_service.submit_claim(params[:education_benefit].except(:form_id), response_data)

        clear_saved_form(params[:form_id]) if params[:form_id]

        render json: {
          data: {
            status: response.status
          }
        }
      rescue => e
        log_submission_error(e, 'MEB submit_claim failed')
        raise
      end

      def enrollment
        claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = claimant_response.claimant_id
        if claimant_id.nil?
          render json: {
            data: {
              no_911_benefits: true
            }
          }
        else
          response = enrollment_service.get_enrollment(claimant_id)
          render json: EnrollmentSerializer.new(response)
        end
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

      def submit_enrollment_verification
        claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = claimant_response.claimant_id

        if claimant_id.to_i.zero?
          render json: {
            data: {
              enrollment_certify_responses: []
            }
          }
        else
          response = enrollment_service.submit_enrollment(
            params[:education_benefit], claimant_id
          )
          render json: SubmitEnrollmentSerializer.new(response)
        end
      end

      def duplicate_contact_info
        response = contact_info_service.check_for_duplicates(params[:emails], params[:phones])
        render json: ContactInfoSerializer.new(response)
      end

      def exclusion_periods
        claimant_response = claimant_service.get_claimant_info(@form_type)
        claimant_id = claimant_response.claimant_id
        exclusion_response = exclusion_period_service.get_exclusion_periods(claimant_id)

        render json: ExclusionPeriodSerializer.new(exclusion_response)
      end

      private

      def set_type
        type = params['type'].presence || 'Chapter33'
        @form_type = type.casecmp('VetTec').zero? ? 'VetTec' : type.capitalize
      end

      def resolve_email_config
        # Get chapter type from params (frontend sends 'chapter1606', 'chapter30', or 'chapter33')
        chapter_type = params[:chapter_type].to_s.downcase

        # Check if 1606/30 confirmation pages feature is enabled and if we have a matching config
        if Flipper.enabled?(:meb_1606_30_confirmation_pages) && CONFIRMATION_EMAIL_CONFIG.key?(chapter_type)
          CONFIRMATION_EMAIL_CONFIG[chapter_type].merge(flipper_key: FLIPPER_KEY)
        else
          # Default to 1990MEB configuration (Chapter 33 or when feature flag is off)
          {
            worker: MebApi::V0::Submit1990mebFormConfirmation,
            form_tag: FORM_TAG,
            flipper_key: FLIPPER_KEY
          }
        end
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

      def contact_info_service
        MebApi::DGI::ContactInfo::Service.new(@current_user)
      end

      def eligibility_service
        MebApi::DGI::Eligibility::Service.new(@current_user)
      end

      def automation_service
        MebApi::DGI::Automation::Service.new(@current_user)
      end

      def submission_service
        MebApi::DGI::Submission::Service.new(@current_user)
      end

      def enrollment_service
        MebApi::DGI::Enrollment::Service.new(@current_user)
      end

      def exclusion_period_service
        MebApi::DGI::ExclusionPeriod::Service.new(@current_user)
      end

      # Fetch unmasked direct deposit if asterisks present. Gracefully handles failures.
      def fetch_direct_deposit_info
        return nil if Rails.env.development?

        account_number = params.dig(:education_benefit, :direct_deposit, :direct_deposit_account_number)
        routing_number = params.dig(:education_benefit, :direct_deposit, :direct_deposit_routing_number)
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

      def generate_dynamic_filename(form_type, is_eligible, timestamp)
        letter_type = is_eligible ? 'CoE' : 'Denial'
        prefix = BENEFIT_TYPE_FILENAME_MAPPING[form_type]

        if prefix
          date = Time.now.getlocal
          date_format = date.strftime('%Y_%m_%d')
          "#{prefix}_#{letter_type}_#{date_format}"
        else
          "Post-9/11 GI_Bill_#{letter_type}_#{timestamp}"
        end
      end
    end
  end
end
