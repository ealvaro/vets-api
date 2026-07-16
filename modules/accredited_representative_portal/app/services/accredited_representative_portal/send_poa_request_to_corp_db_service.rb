# frozen_string_literal: true

module AccreditedRepresentativePortal
  class SendPoaRequestToCorpDbService
    def self.call(poa_request)
      new(poa_request).call
    end

    def initialize(poa_request)
      @poa_request = poa_request
      @claimant_id = poa_request.claimant.icn
      @service = BenefitsClaims::Service.new(@claimant_id)
    end

    def call
      @service.submit_power_of_attorney_request(build_payload)
    rescue Faraday::Error => e
      log_error(e)
      raise
    end

    private

    def build_payload
      {
        data: {
          attributes: {}.tap do |h|
            h[:veteran] = veteran_payload
            if Flipper.enabled?(:form2122_non_veteran_digital_submit) && form_data.fetch('dependent').present?
              h[:claimant] = claimant_payload
            end
            h[:representative] = representative_payload
            h[:recordConsent] = authorizations['recordDisclosureLimitations'].blank?
            h[:consentAddressChange] = authorizations['addressChange'] == true
            h[:consentLimits] = authorizations['recordDisclosureLimitations'] || []
          end
        }
      }
    end

    def veteran_payload
      {
        serviceNumber: veteran['serviceNumber'],
        serviceBranch: veteran['serviceBranch'],
        address: address_payload(veteran['address']),
        phone: phone_payload(veteran['phone']),
        email: veteran['email'],
        insuranceNumber: veteran['insuranceNumber']
      }
    end

    def claimant_payload
      {
        claimantId: @claimant_id,
        address: address_payload(claimant['address'] || {}),
        relationship: claimant['relationship'],
        # optional fields
        dateOfBirth: claimant['dateOfBirth'],
        phone: phone_payload(claimant['phone']),
        email: claimant['email']
      }
    end

    def address_payload(address)
      {
        addressLine1: address['addressLine1'],
        addressLine2: address['addressLine2'],
        city: address['city'],
        stateCode: address['stateCode'],
        zipCode: address['zipCode'],
        zipCodeSuffix: address['zipCodeSuffix'],
        countryCode: address['countryCode'] || 'US'
      }
    end

    def phone_payload(phone)
      digits = (phone || '').gsub(/\D/, '')
      {
        areaCode: digits[0, 3],
        phoneNumber: digits[3, 7]
      }
    end

    def representative_payload
      { poaCode: @poa_request.power_of_attorney_holder_poa_code }
    end

    def form_data
      @form_data ||= @poa_request.power_of_attorney_form.parsed_data
    end

    def veteran
      @veteran ||= form_data.fetch('veteran')
    end

    def claimant
      @claimant ||= form_data.fetch('dependent')
    end

    def authorizations
      @authorizations ||= form_data.fetch('authorizations', {})
    end

    def log_error(error)
      Rails.logger.error(
        'POA CorpDB send failed',
        poa_request_id: @poa_request.id,
        error_class: error.class.name,
        status: error.respond_to?(:response) ? error.response&.[](:status) : nil
      )
    end
  end
end
