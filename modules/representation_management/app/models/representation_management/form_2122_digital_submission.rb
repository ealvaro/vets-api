# frozen_string_literal: true

module RepresentationManagement
  class Form2122DigitalSubmission < RepresentationManagement::Form2122Base
    VALIDATION_ERROR_FORM_ID = '21-22'

    BLANK_ICN = 'ICN value is missing'
    BLANK_PARTICIPANT_ID = 'Corp Participant ID value is blank'
    DEPENDENT_SUBMITTER = 'must submit as the Veteran for digital Power of Attorney Requests'
    DOES_NOT_ACCEPT_DIGITAL_REQUESTS = 'does not accept digital Power of Attorney Requests'
    NOT_FOUND = 'not found'
    REP_CANNOT_ACCEPT = 'representative does not have an active acceptance mode for this organization'

    attr_accessor :dependent, :organization_id, :user

    validates :organization_id, presence: true
    validate :organization_exists?
    validate :organization_accepts_digital_poa_requests?
    validate :representative_can_accept_for_organization?
    validate :user_is_submitting_as_veteran?
    validate :user_has_participant_id?
    validate :user_has_icn?

    # The values of these four checkboxes are unintuitive. Our online form experience asks the user to select
    # what details to share with the representative but the actual 21-22 form asks the user to select what
    # details to withhold from the representative.  So we need to invert the values.
    # See https://va.ghe.com/software/va.gov-team/issues/98295
    def normalized_limitations_of_consent
      if record_consent && consent_limits.empty?
        []
      elsif record_consent
        LIMITATIONS_OF_CONSENT.difference(consent_limits)
      else
        LIMITATIONS_OF_CONSENT
      end
    end

    def organization
      return @organization if defined? @organization

      @organization = find_organization
    end

    private

    def find_organization
      if appoint_accredited_models_enabled?
        AccreditedOrganization.find_by(poa_code: organization_id)
      else
        Veteran::Service::Organization.find_by(poa: organization_id)
      end
    end

    def organization_exists?
      return unless organization.nil?

      errors.add(:organization, NOT_FOUND)
    end

    def organization_accepts_digital_poa_requests?
      return if organization&.can_accept_digital_poa_requests

      errors.add(:organization, DOES_NOT_ACCEPT_DIGITAL_REQUESTS)
    end

    def representative_can_accept_for_organization?
      return if organization.nil? || representative.nil?
      return unless organization.can_accept_digital_poa_requests

      poa_code = organization.respond_to?(:poa) ? organization.poa : organization.poa_code
      return if representative_accepts_for_poa_code?(poa_code)

      errors.add(:representative, REP_CANNOT_ACCEPT)
    end

    # The acceptance-mode lookup is gated by the Appoint a Rep migration flag: when on it reads the
    # AccreditedX Accreditation join, when off it reads the legacy
    # Veteran::Service::OrganizationRepresentative join. poa_code and the rep registration number are
    # identical on both sides.
    def representative_accepts_for_poa_code?(poa_code)
      if appoint_accredited_models_enabled?
        Accreditation.active
                     .for_organization_poa_codes(poa_code)
                     .for_registration_numbers(representative_registration_number)
                     .where.not(acceptance_mode: 'no_acceptance')
                     .exists?
      else
        Veteran::Service::OrganizationRepresentative.active
                                                    .where(representative_id:, organization_poa: poa_code)
                                                    .where.not(acceptance_mode: 'no_acceptance')
                                                    .exists?
      end
    end

    def representative_registration_number
      if representative.is_a?(AccreditedIndividual)
        representative.registration_number
      else
        representative.representative_id
      end
    end

    def user_is_submitting_as_veteran?
      return if Flipper.enabled?(:form2122_non_veteran_digital_submit)
      return unless dependent

      errors.add(:user, DEPENDENT_SUBMITTER)
    end

    def user_has_participant_id?
      return if user.participant_id.present?

      errors.add(:user, BLANK_PARTICIPANT_ID)
    end

    def user_has_icn?
      return if user.icn.present?

      errors.add(:user, BLANK_ICN)
    end

    def validation_error_message
      'Power of attorney request form validation failed'
    end
  end
end
