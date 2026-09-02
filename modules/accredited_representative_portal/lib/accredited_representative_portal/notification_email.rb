# frozen_string_literal: true

require 'accredited_representative_portal/notification_callback'
require 'veteran_facing_services/notification_email/saved_claim'

module AccreditedRepresentativePortal
  class NotificationEmail < ::VeteranFacingServices::NotificationEmail::SavedClaim
    BENEFIT_TYPE_LABELS = {
      'compensation' => 'Disability compensation (VA Form 21-526EZ)',
      'pension' => 'Pension (VA Form 21P-527EZ)',
      'survivor' => 'Survivor benefits'
    }.freeze

    # registration_number is only unique when scoped to individual_type (see the unique index on
    # accredited_individuals), so the recipient's type must be included when resolving the record.
    POA_HOLDER_TYPE_TO_INDIVIDUAL_TYPE = {
      PowerOfAttorneyHolder::Types::VETERAN_SERVICE_ORGANIZATION =>
        AccreditedIndividual::INDIVIDUAL_TYPE_VSO_REPRESENTATIVE,
      PowerOfAttorneyHolder::Types::ATTORNEY => AccreditedIndividual::INDIVIDUAL_TYPE_ATTORNEY,
      PowerOfAttorneyHolder::Types::CLAIMS_AGENT => AccreditedIndividual::INDIVIDUAL_TYPE_CLAIM_AGENT
    }.freeze

    def initialize(saved_claim_id)
      super(saved_claim_id, service_name: 'accredited_representative_portal')
    end

    private

    # Not all accredited representatives have an email on record (and some registration numbers may
    # not resolve to a record at all). Sending is impossible in that case, so run the base class
    # validations and only intercept the resulting `Missing email` failure: skip gracefully and emit
    # a low-severity signal rather than letting it route through `send_failure` and generate error
    # alerts for what is an expected data condition. Every other validation/guardrail is preserved.
    def valid_attempt?(email_type, resend: false)
      super
    rescue VeteranFacingServices::NotificationEmail::FailureToSend => e
      raise unless e.message == 'Missing email'

      log_missing_representative_email(email_type)
      false
    end

    def log_missing_representative_email(email_type)
      poa_holder_type = saved_claim_claimant_representative&.power_of_attorney_holder_type
      Rails.logger.warn(
        "AccreditedRepresentativePortal::NotificationEmail: skipping #{email_type} delivery; " \
        'no email available for representative (record unresolved or email missing) ' \
        "(form_id: #{form_id}, saved_claim_id: #{claim.id}, poa_holder_type: #{poa_holder_type})"
      )
      StatsD.increment(
        'accredited_representative_portal.notification_email.skipped_missing_email',
        tags: ["email_type:#{email_type}", "form_id:#{form_id}"]
      )
    end

    def claim_class
      ::SavedClaim
    end

    def form_id
      if claim.class.const_defined?(:PROPER_FORM_ID)
        claim.class::PROPER_FORM_ID
      elsif claim.class.const_defined?(:FORM_ID)
        claim.class::FORM_ID
      else
        claim.form_id
      end
    end

    def saved_claim_claimant_representative
      @saved_claim_claimant_representative ||=
        SavedClaimClaimantRepresentative.find_by(saved_claim_id: claim.id)
    end

    def representative
      @representative ||= begin
        rep_id = saved_claim_claimant_representative&.accredited_individual_registration_number
        find_representative(rep_id) if rep_id
      end
    end

    def find_representative(rep_id)
      if AccreditedRepresentativePortal.use_accredited_models?
        individual_type =
          POA_HOLDER_TYPE_TO_INDIVIDUAL_TYPE[saved_claim_claimant_representative&.power_of_attorney_holder_type]
        return if individual_type.blank?

        AccreditedIndividual.find_by(registration_number: rep_id, individual_type:)
      else
        Veteran::Service::Representative.find_by(representative_id: rep_id)
      end
    end

    def personalization
      default = super

      {
        'form_id' => form_id,
        'confirmation_number' => claim&.latest_submission_attempt&.benefits_intake_uuid || claim&.confirmation_number,
        'first_name' => representative&.first_name || 'Representative',
        'submission_date' => claim&.created_at&.strftime('%B %-d, %Y'),
        'benefit_type' => BENEFIT_TYPE_LABELS[parsed_form['benefitType']]
      }.compact.reverse_merge(default)
    end

    def parsed_form
      @parsed_form ||= JSON.parse(claim.form)
    rescue JSON::ParserError
      {}
    end

    def email
      representative&.email
    end

    def callback_klass
      AccreditedRepresentativePortal::NotificationCallback.to_s
    end

    def callback_metadata
      super.merge(claim_id: claim.id)
    end
  end
end
