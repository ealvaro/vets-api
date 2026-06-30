# frozen_string_literal: true

require 'saml/user_attributes/ssoe'
require 'base64'

module SAML
  class User
    UNKNOWN_AUTHN_CONTEXT = 'unknown'
    MHV_ORIGINAL_CSID = 'mhv'
    MHV_MAPPED_CSID = 'myhealthevet'
    IDME_CSID = 'idme'
    LOGINGOV_CSID = 'logingov'
    CLEAR_CSID = 'clear'

    AUTHN_CONTEXTS = {
      LOA::IDME_LOA1_VETS => { loa_current: LOA::ONE, sign_in: { service_name: IDME_CSID } },
      LOA::IDME_LOA1_2FA => { loa_current: LOA::ONE, sign_in: { service_name: IDME_CSID } },
      LOA::IDME_LOA1_MFA => { loa_current: LOA::ONE, sign_in: { service_name: IDME_CSID } },
      LOA::IDME_LOA3_VETS => { loa_current: LOA::THREE, sign_in: { service_name: IDME_CSID } },
      LOA::IDME_LOA3 => { loa_current: LOA::THREE, sign_in: { service_name: IDME_CSID } },
      IAL::IDME_IAL2 => { loa_current: LOA::THREE, sign_in: { service_name: IDME_CSID } },
      'multifactor' => { loa_current: nil, sign_in: { service_name: IDME_CSID } },
      'myhealthevet_multifactor' => { loa_current: nil, sign_in: { service_name: MHV_ORIGINAL_CSID } },
      'myhealthevet_loa3' => { loa_current: LOA::THREE, sign_in: { service_name: MHV_ORIGINAL_CSID } },
      'myhealthevet' => { loa_current: nil, sign_in: { service_name: MHV_ORIGINAL_CSID } },
      LOA::IDME_LOA3_2FA => { loa_current: LOA::THREE, sign_in: { service_name: IDME_CSID } },
      LOA::IDME_LOA3_MFA => { loa_current: LOA::THREE, sign_in: { service_name: IDME_CSID } },
      IAL::LOGIN_GOV_IAL1 => { loa_current: LOA::ONE, sign_in: { service_name: LOGINGOV_CSID } },
      IAL::LOGIN_GOV_IAL1_2FA => { loa_current: LOA::ONE, sign_in: { service_name: LOGINGOV_CSID } },
      IAL::LOGIN_GOV_IAL1_MFA => { loa_current: LOA::ONE, sign_in: { service_name: LOGINGOV_CSID } },
      IAL::LOGIN_GOV_IAL2 => { loa_current: LOA::THREE, sign_in: { service_name: LOGINGOV_CSID } },
      IAL::LOGIN_GOV_IAL2_2FA => { loa_current: LOA::THREE, sign_in: { service_name: LOGINGOV_CSID } },
      IAL::LOGIN_GOV_IAL2_MFA => { loa_current: LOA::THREE, sign_in: { service_name: LOGINGOV_CSID } }
    }.freeze

    LOGIN_TYPES = [MHV_ORIGINAL_CSID, IDME_CSID, LOGINGOV_CSID, CLEAR_CSID].freeze

    attr_reader :saml_response, :saml_attributes, :user_attributes, :tracker_uuid

    delegate :to_hash, to: :user_attributes
    delegate :needs_csp_id_mpi_update?, to: :user_attributes

    def initialize(saml_response)
      @saml_response = saml_response
      @saml_attributes = saml_response.attributes
      @tracker_uuid = saml_response.in_response_to
      @user_attributes = SAML::UserAttributes::SSOe.new(saml_attributes, authn_context, tracker_uuid)
    end

    delegate :validate!, to: :@user_attributes

    def changing_multifactor?
      return false if authn_context.nil?

      authn_context.include?('multifactor')
    end

    private

    def authn_context
      saml_response.authn_context_text
    rescue
      context = {
        controller_name: 'sessions',
        sign_in_method: 'not-signed-in:error',
        sign_in_service_name: user_attributes&.sign_in&.fetch(:service_name, nil),
        sign_in_account_type: user_attributes&.sign_in&.fetch(:account_type, nil),
        sign_in_auth_broker: user_attributes&.sign_in&.fetch(:auth_broker, nil)
      }
      Rails.logger.error('authn_context error', context)

      raise
    end
  end
end
