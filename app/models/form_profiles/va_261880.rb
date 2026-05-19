# frozen_string_literal: true

class FormProfiles::VA261880 < FormProfile
  def self.form_filename_and_version(form_id, current_user)
    if Flipper.enabled?(:coe_form_v3_lgy_fields, current_user)
      ["#{form_id}v3", 3]
    elsif Flipper.enabled?(:coe_form_rebuild_cveteam, current_user)
      ["#{form_id}v2", 2]
    else
      [form_id, 1]
    end
  end

  def prefill
    @identity_information = initialize_identity_information
    @contact_information = initialize_contact_information
    @military_information = initialize_military_information

    versioned_form_id, version_number = self.class.form_filename_and_version(form_id, @user)

    mappings = self.class.mappings_for_form(versioned_form_id)
    form_data = generate_prefill(mappings)

    form_data['version'] = version_number if version_number > 1

    { form_data:, metadata: }
  end

  def metadata
    {
      version: 0,
      prefill: true,
      returnUrl: '/applicant-information'
    }
  end

  private

  def v2_mailing_address
    addr = @contact_information&.address
    return nil unless addr

    {
      address_line1: addr.street,
      address_line2: addr.street2,
      city: addr.city,
      state_code: addr.state,
      zip_code: addr.postal_code
    }
  end

  def v2_home_phone
    phone = @contact_information&.us_phone
    return nil if phone.blank?

    digits = phone.gsub(/\D/, '')
    return nil unless digits.length == 10

    {
      area_code: digits[0, 3],
      country_code: '1',
      phone_number: digits[3, 7]
    }
  end

  def v2_email
    email = @contact_information&.email
    return nil if email.blank?

    { email_address: email }
  end
end
