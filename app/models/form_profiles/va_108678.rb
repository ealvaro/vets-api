# frozen_string_literal: true

# FormProfile for VA Form 10-8678
# Annual Clothing Allowance
class FormProfiles::VA108678 < FormProfile
  class FormAddress
    include Vets::Model

    attribute :country_name, String
    attribute :address_line1, String
    attribute :address_line2, String
    attribute :address_line3, String
    attribute :city, String
    attribute :state_code, String
    attribute :province, String
    attribute :zip_code, String
    attribute :international_postal_code, String
  end

  def metadata
    {
      version: 0,
      prefill: true,
      returnUrl: '/personal-information'
    }
  end

  ##
  # Prefills the form data with identity and contact information
  #
  # This method initializes identity and contact information, converts the country code
  # to ISO2 format if present, and maps data according to form-specific mappings
  #
  # @return [Hash]
  def prefill
    # return { form_data: {}, metadata: } unless prefill_enabled?

    @identity_information = initialize_identity_information
    @military_information = initialize_military_information
    @contact_information = initialize_contact_information
    contact_information.email ||= user.email
    contact_information.us_phone ||= user&.home_phone&.gsub(/\D/, '')

    prefill_form_address
    mappings = self.class.mappings_for_form(form_id)

    form_data = generate_prefill(mappings) if FormProfile.prefill_enabled_forms.include?(form_id)

    if form_data['fullName']['middle']
      form_data['fullName']['middle'] = initial_letter_or_blank(form_data['fullName']['middle'])
    end

    { form_data:, metadata: }
  end

  private

  def prefill_form_address
    begin
      mailing_address = VAProfileRedis::V2::ContactInformation.for_user(user).mailing_address
    rescue => e
      Rails.logger.warn('10-8678::FormProfile Problem Extracting Address', { error: e.message })
      mailing_address = {}
    end

    return if mailing_address.blank?

    zip_code = mailing_address.zip_code.presence || mailing_address.international_postal_code.presence
    @form_address = FormAddress.new(
      mailing_address.to_h.slice(
        :address_line1, :address_line2, :address_line3,
        :city, :state_code, :province
      ).merge(country_name: mailing_address.country_code_iso3, zip_code:)
    )
  end

  def initial_letter_or_blank(middle_name = '')
    middle_name.blank? ? '' : middle_name[0]
  end
end
