# frozen_string_literal: true

require 'sign_in/oauth/service'
require 'sign_in/idme/configuration'

module SignIn
  module Idme
    class Service < SignIn::OAuth::Service
      configuration Configuration

      attr_accessor :type

      def initialize(type:, optional_scopes: [])
        @type = type
        super(optional_scopes:)
      end

      def build_user_info(decoded_jwt)
        info = decoded_jwt.with_indifferent_access

        OAuth::UserInfo.new(
          sub: info[:sub],
          email: info[:email],
          all_emails: info[:emails_confirmed],
          multifactor: info[:multifactor],
          first_name: info[:fname],
          last_name: info[:lname],
          ssn: info[:social],
          birth_date: info[:birth_date],
          phone_number: info[:phone],
          address: normalize_address(info),
          level_of_assurance: info[:level_of_assurance] || default_level_of_assurance(info),
          credential_ial: info[:credential_ial] || default_credential_ial(info),
          icn: info[:mhv_icn],
          mhv_credential_uuid: info[:mhv_uuid],
          mhv_assurance: info[:mhv_assurance]
        )
      end

      private

      def credential_attributes(user_info)
        type_attributes(user_info).merge(
          idme_uuid: user_info.sub,
          service_name: type,
          all_csp_emails: user_info.all_emails,
          multifactor: user_info.multifactor
        )
      end

      def type_attributes(user_info)
        case type
        when OAuth::Constants::IDME
          {
            ssn: user_info.ssn,
            birth_date: user_info.birth_date,
            first_name: user_info.first_name,
            last_name: user_info.last_name,
            address: user_info.address,
            phone_number: user_info.phone_number
          }
        when OAuth::Constants::MHV
          {
            mhv_credential_uuid: user_info.mhv_credential_uuid,
            mhv_icn: user_info.icn,
            mhv_assurance: user_info.mhv_assurance
          }
        end
      end

      def token_success_log(code, response)
        "#{config.log_prefix} Token Success, code: #{code}, scope: #{response.body[:scope]}"
      end

      def parse_user_info(response)
        decrypted_jwe = jwe_decrypt(JSON.parse(response.body))
        decoded_jwt = jwt_decode(decrypted_jwe)
        log_credential(decoded_jwt) if config.log_credential

        build_user_info(decoded_jwt)
      end

      def default_level_of_assurance(info)
        info[:lname] ? OAuth::Constants::LOA_THREE : OAuth::Constants::LOA_ONE
      end

      def default_credential_ial(info)
        info[:lname] ? OAuth::Constants::IAL_TWO : OAuth::Constants::IAL_ONE
      end

      def error_description(client_error)
        client_error.body && client_error.body[:error_description]
      end

      def auth_params(acr, state, operation, **)
        override = override_acr_values?(acr[:acr], acr[:acr_values])
        scoped_acr = append_optional_scopes(acr[:acr], override)
        acr_values = override ? nil : acr[:acr_values]

        base_auth_params(state).merge(
          scope: scoped_acr,
          acr_values:,
          op: convert_operation(operation)
        ).compact
      end

      def log_rendering_auth(state:, acr:, operation:, params_hash:)
        override = override_acr_values?(acr[:acr], acr[:acr_values])
        scoped_acr = params_hash[:scope]
        acr_values = params_hash[:acr_values]

        Rails.logger.info("#{config.log_prefix} Rendering auth, " \
                          "state: #{state}, acr: #{scoped_acr}, operation: #{operation}",
                          acr: scoped_acr, acr_values:, operation:, override:)
      end

      def convert_operation(operation)
        case operation
        when OAuth::Constants::SIGN_UP
          config.sign_up_operation
        end
      end

      def get_authn_context(current_ial)
        case type
        when OAuth::Constants::IDME
          current_ial == OAuth::Constants::IAL_TWO ? OAuth::Constants::IDME_LOA3 : OAuth::Constants::IDME_LOA1
        when OAuth::Constants::MHV
          current_ial == OAuth::Constants::IAL_TWO ? OAuth::Constants::IDME_MHV_LOA3 : OAuth::Constants::IDME_MHV_LOA1
        end
      end

      def normalize_address(info)
        return unless address_defined?(info)

        {
          street: info[:street],
          postal_code: info[:zip],
          state: info[:state],
          city: info[:city],
          country: USA_COUNTRY_CODE
        }
      end

      def address_defined?(info)
        info[:street] && info[:zip] && info[:state] && info[:city]
      end

      def jwe_decrypt(encrypted_jwe)
        JWE.decrypt(encrypted_jwe, config.ssl_key)
      rescue JWE::DecodeError
        raise OAuth::Errors::JWEDecodeError, "#{config.log_prefix} JWE is malformed"
      end

      def log_credential(credential)
        MockedAuthentication::Mockdata::Writer.save_credential(credential:, credential_type: type)
      end

      def token_params(code, *)
        {
          grant_type: config.grant_type,
          code:,
          client_id: config.client_id,
          client_secret: config.client_secret,
          redirect_uri: config.redirect_uri
        }
      end

      def append_optional_scopes(acr, override)
        return acr unless optional_scopes.any?

        if override
          "#{OAuth::Constants::IDME_LOA3_FORCE}/#{optional_scopes.join('/')}"
        else
          return acr unless acr == OAuth::Constants::IDME_LOA3_FORCE

          "#{acr}/#{optional_scopes.join('/')}"
        end
      end

      def facial_match_preferred_acr_values
        [OAuth::Constants::IDME_COMPARISON_MINIMUM,
         OAuth::Constants::IDME_IAL2,
         OAuth::Constants::IDME_LOA3].join(' ')
      end

      def override_acr_values?(acr, acr_values)
        optional_scopes.any? &&
          acr == OAuth::Constants::IDME_IAL1 &&
          acr_values == facial_match_preferred_acr_values &&
          Flipper.enabled?('identity_idme_ial2_full_enforcement')
      end

      def default_acr
        OAuth::Constants::IDME_LOA1
      end
    end
  end
end
