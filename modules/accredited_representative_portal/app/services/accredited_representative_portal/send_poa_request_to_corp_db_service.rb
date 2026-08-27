# frozen_string_literal: true

# TODO: Most of this service is duplicated code from AccreditedRepresentativePortal::PowerOfAttorneyRequestService::Accept
#   Move all shared code to a shared location to DRY it up and to reduce discrepancies and errors
module AccreditedRepresentativePortal
  class SendPoaRequestToCorpDbService
    def self.call(poa_request)
      new(poa_request).call
    end

    def initialize(poa_request)
      @poa_request = poa_request
      @service = BenefitsClaims::Service.new(veteran_icn)
    end

    def call
      @service.submit_power_of_attorney_request(build_payload)
    rescue Faraday::Error => e
      log_error(e)
      raise
    end

    private

    def dependent_claimant?
      @poa_request.claimant_type == PowerOfAttorneyRequest::ClaimantTypes::DEPENDENT
    end

    def veteran_icn
      if Flipper.enabled?(:form2122_non_veteran_digital_submit) && dependent_claimant?
        veteran_data = {
          first_name: form_data.dig('veteran', 'name', 'first'),
          last_name: form_data.dig('veteran', 'name', 'last'),
          ssn: form_data.dig('veteran', 'ssn'),
          birth_date: form_data.dig('veteran', 'dateOfBirth')
        }
        @veteran_icn ||= ClaimantLookupService.get_icn(
          veteran_data[:first_name],
          veteran_data[:last_name],
          veteran_data[:ssn],
          veteran_data[:birth_date]
        )
      else
        @veteran_icn ||= claimant_icn
      end
    end

    def claimant_icn
      @poa_request.claimant.icn
    end

    def build_payload
      {
        data: {
          attributes: {}.tap do |h|
            h[:veteran] = veteran_payload
            if Flipper.enabled?(:form2122_non_veteran_digital_submit) && dependent_claimant?
              h[:claimant] = claimant_payload
            end
            h[:representative] = representative_payload

            h[:recordConsent] = authorizations['recordDisclosureLimitations'].blank?
            h[:consentLimits] = authorizations['recordDisclosureLimitations'] || []
            h[:consentAddressChange] = authorizations['addressChange'] == true

            Common::HashHelpers.deep_remove_blanks(h) # removes nil and blank values (but not false)
          end
        }
      }
    end

    def veteran_payload
      return nil if veteran.blank?

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
      return nil if claimant.blank?

      {
        claimantId: claimant_icn,
        address: address_payload(claimant['address']),
        relationship: claimant['relationship'],
        # optional fields
        dateOfBirth: claimant['dateOfBirth'],
        phone: phone_payload(claimant['phone']),
        email: claimant['email']
      }
    end

    def address_payload(address)
      return nil if address.blank?

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
      return nil if phone.blank?

      phone_number = phone.to_s.gsub(/-| /, '')
      {}.tap do |p|
        p[:areaCode] = phone_number[0..2]
        p[:phoneNumber] = phone_number[3..9]
      end
    end

    def representative_payload
      { poaCode: @poa_request.power_of_attorney_holder_poa_code }
    end

    def form_data
      @form_data ||= @poa_request.power_of_attorney_form.parsed_data
    end

    def veteran
      @veteran ||= form_data['veteran']
    end

    def claimant
      @claimant ||= form_data['dependent']
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
