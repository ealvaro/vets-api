# frozen_string_literal: true

module IncreaseCompensation
  ##
  # Form profile for VA Form 21-8940 (APPLICATION FOR INCREASED COMPENSATION BASED ON UNEMPLOYABILITY)
  # extends app/models/form_profile.rb, which handles form prefill
  class FormProfiles::VA218940v1 < FormProfile
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

    class DisabilityList
      include Vets::Model

      attribute :rated_disabilities, Array
    end

    attribute :form_address, FormAddress
    attribute :rated_disabilities_information, DisabilityList

    ##
    # Returns metadata related to the form profile
    #
    # @return [Hash]
    def metadata
      {
        version: 0,
        prefill: prefill_enabled?,
        returnUrl: '/confirmation-question'
      }
    end

    def prefill_enabled?
      Flipper.enabled?(:form_218940_prefill_enabled) || false
    end

    ##
    # Prefills the form data with identity and contact information
    #
    # This method initializes identity and contact information, converts the country code
    # to ISO2 format if present, and maps data according to form-specific mappings
    #
    # @return [Hash]
    def prefill
      @contact_information = initialize_contact_information
      @identity_information = initialize_identity_information
      if Flipper.enabled?(:form_218940_disability_prefill_enabled)
        @rated_disabilities_information = initialize_rated_disabilities_information
      end

      contact_information.email ||= user.email
      contact_information.us_phone ||= user&.home_phone&.gsub(/\D/, '')
      prefill_form_address

      mappings = self.class.mappings_for_form(form_id)
      form_data = generate_prefill(mappings) if FormProfile.prefill_enabled_forms.include?(form_id)
      form_data['ratedDisabilitiesFetchFailed'] = true if @rated_disabilities_fetch_failed && form_data

      { form_data:, metadata: }
    end

    ##
    # Retrieves the last four digits of the VA file number or SSN from BGS
    #
    # @return [String]
    def va_file_number
      response = BGS::People::Request.new.find_person_by_participant_id(user:)
      response.file_number.presence || user.ssn.presence
    end

    private

    def prefill_form_address
      begin
        mailing_address = VAProfileRedis::V2::ContactInformation.for_user(user).mailing_address
      rescue => e
        Rails.logger.warn('IncreaseCompensation::FormProfile Problem Extrating Address', { error: e.message })
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

    def initialize_rated_disabilities_information
      return {} unless user.authorize :evss, :access?
      return {} unless user.authorize :lighthouse, :access_vet_status?

      fetch_rated_disabilities_information
    rescue => e
      Rails.logger.error('IncreaseCompensation::FormProfile Fetch Disabilities Error', { error: e.message })
      @rated_disabilities_fetch_failed = true
      DisabilityList.new(rated_disabilities: [])
    end

    def fetch_rated_disabilities_information
      api_provider = ApiProviderFactory.call(
        type: ApiProviderFactory::FACTORIES[:rated_disabilities],
        provider: :lighthouse,
        options: { icn: user.icn.to_s },
        current_user: user,
        feature_toggle: :form_218940_disability_prefill_enabled
      )
      invoker = 'FormProfiles::VA218940V1#initialize_rated_disabilities_information'
      response = api_provider.get_rated_disabilities(nil, nil, { invoker: })

      simple_response = response.rated_disabilities
                                .select { |rated_dis| rated_dis.decision_code == 'SVCCONNCTED' }
                                .map { |disability_info| { 'disability' => disability_info.name } }

      DisabilityList.new(rated_disabilities: simple_response)
    end
  end
end
