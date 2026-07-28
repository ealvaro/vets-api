# frozen_string_literal: true

require 'sign_in/oauth/service'
require 'sign_in/logingov/configuration'

module SignIn
  module Logingov
    class Service < SignIn::OAuth::Service
      configuration Configuration

      DEFAULT_SCOPES = [
        PROFILE_SCOPE = 'profile',
        VERIFIED_AT_SCOPE = 'profile:verified_at',
        ADDRESS_SCOPE = 'address',
        EMAIL_SCOPE = 'email',
        OPENID_SCOPE = 'openid',
        SSN_SCOPE = 'social_security_number'
      ].freeze

      def render_logout(client_id, client_logout_redirect_uri)
        logout_state = encode_logout_redirect(client_id, client_logout_redirect_uri)

        "#{config.logout_url}?#{sign_out_params(config.logout_redirect_uri, logout_state).to_query}"
      end

      def render_logout_redirect(state)
        state_payload = decode_logout_state(state)

        URI.parse(state_payload['logout_redirect']).to_s
      end

      def decode_logout_state(state)
        JWT.decode(state, config.ssl_key.public_key, true, { algorithm: 'RS256' }).first
      rescue JWT::DecodeError => e
        raise OAuth::Errors::JWTDecodeError, "#{config.log_prefix} State is malformed: #{e.message}"
      end

      def build_user_info(body)
        info = body.with_indifferent_access

        OAuth::UserInfo.new(
          sub: info[:sub],
          email: info[:email],
          all_emails: info[:all_emails],
          multifactor: true,
          first_name: info[:given_name],
          last_name: info[:family_name],
          ssn: info[:social_security_number],
          birth_date: info[:birthdate],
          address: normalize_address(info[:address]),
          verified_at: info[:verified_at]
        )
      end

      private

      def default_acr
        OAuth::Constants::LOGIN_GOV_IAL1
      end

      def parse_user_info(response)
        log_credential(response.body) if config.log_credential
        build_user_info(response.body)
      end

      def credential_attributes(user_info)
        {
          logingov_uuid: user_info.sub,
          ssn: user_info.ssn,
          birth_date: user_info.birth_date,
          first_name: user_info.first_name,
          last_name: user_info.last_name,
          address: user_info.address,
          all_csp_emails: user_info.all_emails,
          multifactor: user_info.multifactor,
          service_name: config.service_name
        }
      end

      def parse_token_response(response_body)
        access_token = response_body[:access_token]
        logingov_acr = jwt_decode(response_body[:id_token])['acr']

        { access_token:, logingov_acr: }
      end

      def auth_params(acr, state, _operation)
        base_auth_params(state).merge(
          acr_values: acr[:acr],
          nonce: random_seed,
          prompt: config.prompt,
          scope: (DEFAULT_SCOPES + optional_scopes).join(' ')
        )
      end

      def log_rendering_auth(state:, acr:, operation:, **)
        Rails.logger.info("#{config.log_prefix} Rendering auth, " \
                          "state: #{state}, acr: #{acr[:acr]}, operation: #{operation}, " \
                          "optional_scopes: #{optional_scopes}", acr: acr[:acr], operation:, optional_scopes:)
      end

      def normalize_address(address)
        return unless address

        street_array = address[:street_address].split("\n")
        {
          street: street_array[0],
          street2: street_array[1],
          postal_code: address[:postal_code],
          state: address[:region],
          city: address[:locality],
          country: USA_COUNTRY_CODE
        }
      end

      def get_authn_context(current_ial)
        current_ial == OAuth::Constants::IAL_TWO ? OAuth::Constants::LOGIN_GOV_IAL2 : OAuth::Constants::LOGIN_GOV_IAL1
      end

      def sign_out_params(redirect_uri, state)
        {
          client_id: config.client_id,
          post_logout_redirect_uri: redirect_uri,
          state:
        }
      end

      def token_params(code, *)
        {
          grant_type: config.grant_type,
          code:,
          client_assertion_type: config.client_assertion_type,
          client_assertion: client_assertion_jwt
        }
      end

      def encode_logout_redirect(client_id, logout_redirect_uri)
        JWT.encode(logout_state_payload(client_id, logout_redirect_uri), config.ssl_key, 'RS256')
      end

      def logout_state_payload(client_id, logout_redirect_uri)
        {
          client_id:,
          logout_redirect: logout_redirect_uri,
          seed: random_seed
        }
      end

      def client_assertion_jwt
        jwt_payload = {
          iss: config.client_id,
          sub: config.client_id,
          aud: config.token_url,
          jti: SecureRandom.hex,
          nonce: random_seed,
          exp: Time.now.to_i + config.client_assertion_expiration_seconds
        }
        JWT.encode(jwt_payload, config.ssl_key, 'RS256')
      end

      def random_seed
        @random_seed ||= SecureRandom.hex
      end
    end
  end
end
