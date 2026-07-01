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

    def initialize(saved_claim_id)
      super(saved_claim_id, service_name: 'accredited_representative_portal')
    end

    private

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
        # registration_number uniqueness is scoped to individual_type, but it's unique in
        # practice and only first_name/email are needed here, so resolving by it alone is fine.
        AccreditedIndividual.find_by(registration_number: rep_id)
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
