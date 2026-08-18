# frozen_string_literal: true

module VHA107959f2Prefill
  # Address shape for FMP prefill: includes street3 + isMilitary for addressUI.
  class FormAddress < ::FormAddress
    attribute :street3, String
    attribute :is_military, Bool
  end

  # Extends shared FormContactInformation with residential address for FMP only.
  class FormContactInformation < ::FormContactInformation
    attribute :address, FormAddress
    attribute :residential_address, FormAddress
  end
end

class FormProfiles::VHA107959f2 < FormProfile
  FORM_ID = '10-7959F-2'

  def metadata
    {
      version: 0,
      prefill: prefill_enabled?,
      returnUrl: '/personal-information'
    }
  end

  def prefill_enabled?
    Flipper.enabled?(:form_107959f2_prefill_enabled, user)
  end

  def prefill
    return { form_data: {}, metadata: } unless prefill_enabled?

    super
  end

  private

  def initialize_contact_information
    base = super
    VHA107959f2Prefill::FormContactInformation.new(
      address: address_for_prefill(vet360_contact_info&.mailing_address) || fallback_mailing_address(base.address),
      home_phone: base.home_phone,
      us_phone: base.us_phone,
      mobile_phone: base.mobile_phone,
      email: base.email,
      residential_address: address_for_prefill(vet360_contact_info&.residential_address)
    )
  end

  def address_for_prefill(address)
    return if address.blank?

    hash = {
      street: address.address_line1,
      street2: address.address_line2,
      street3: address.address_line3,
      city: address.city,
      state: address.state_code || address.province,
      country: address.country_code_iso3,
      postal_code: address.zip_plus_four || address.international_postal_code,
      is_military: (true if address.address_type == VAProfile::Models::Address::MILITARY)
    }.compact

    format_address!(hash)
    VHA107959f2Prefill::FormAddress.new(hash)
  end

  def fallback_mailing_address(address)
    return if address.blank?

    hash = {
      street: address.street,
      street2: address.street2,
      city: address.city,
      state: address.state,
      country: address.country,
      postal_code: address.postal_code
    }.compact

    format_address!(hash)
    VHA107959f2Prefill::FormAddress.new(hash)
  end

  def format_address!(hash)
    if hash[:street] && hash[:street2].blank? && (apt = hash[:street].match(APT_REGEX))
      hash[:street2] = apt[1]
      hash[:street] = hash[:street].gsub(/\W?\s+#{apt[1]}/, '').strip
    end

    return unless hash[:postal_code]
    return unless hash[:country] == 'USA'

    hash[:postal_code] = hash[:postal_code][0..4]
  end
end
