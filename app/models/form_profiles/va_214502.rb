# frozen_string_literal: true

# FormProfile for VA Form 21-4502
class FormProfiles::VA214502 < FormProfile
  def metadata
    {
      version: 0,
      prefill: prefill_enabled?,
      returnUrl: '/eligibility'
    }
  end

  def prefill_enabled?
    Flipper.enabled?(:form214502_prefill_enabled)
  end

  ##
  # Prefills the form data with identity and contact information
  #
  # This method initializes identity and contact information, converts the country code
  # to ISO2 format if present, and maps data according to form-specific mappings
  #
  # @return [Hash]
  def prefill
    return { form_data: {}, metadata: } unless prefill_enabled? && prefill_configured?

    @identity_information = initialize_identity_information
    @military_information = initialize_military_information
    @contact_information = initialize_contact_information
    contact_information.email ||= user.email
    contact_information.us_phone ||= user&.home_phone&.gsub(/\D/, '')

    mappings = self.class.mappings_for_form(form_id)

    form_data = generate_prefill(mappings)

    { form_data:, metadata: }
  end

  ##
  # Retrieves the VA file number or SSN from BGS
  #
  # @return [String]
  def va_file_number
    response = BGS::People::Request.new.find_person_by_participant_id(user:)
    response.file_number.presence || user.ssn.presence
  rescue => e
    Rails.logger.warn(
      'Form 21-4502::FormProfile Problem Extracting file_number',
      { exception_class: e.class.to_s, error: e.message }
    )
  end

  def prefill_configured?
    FormProfile.prefill_enabled_forms.include?(form_id)
  end
end
