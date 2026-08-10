# frozen_string_literal: true

require 'sign_in/public_jwks'
require 'sign_in/oauth/constants'
require 'sign_in/oauth/errors'
require 'sign_in/oauth/user_info'
require 'sign_in/credential_attributes_digester'
require 'mockdata/writer'

module SignIn
  module OAuth
    class Service < Common::Client::Base
      include SignIn::PublicJwks

      OPTIONAL_SCOPES = [ALL_EMAILS_SCOPE = 'all_emails'].freeze
      USA_COUNTRY_CODE = 'USA'

      attr_reader :optional_scopes

      def initialize(optional_scopes: [])
        @optional_scopes = valid_optional_scopes(optional_scopes)
        super()
      end

      def render_auth(state: SecureRandom.hex, acr: { acr: default_acr }, operation: Constants::AUTHORIZE, prompt: nil)
        params_hash = auth_params(acr, state, operation, prompt:)
        log_rendering_auth(state:, acr:, operation:, params_hash:)

        "#{config.auth_url}?#{params_hash.to_query}"
      end

      def normalized_attributes(user_info, credential_level)
        base_attributes(user_info, credential_level)
          .merge(credential_attributes(user_info))
          .tap { |attributes| attributes[:digest] = credential_attributes_digest(attributes, user_info.sub) }
      end

      def token(code, ...)
        headers = { 'Content-Type' => token_content_type }
        params = token_params(code, ...)

        response = perform(:post, config.token_path, encode_token_params(params), headers)
        Rails.logger.info(token_success_log(code, response))

        parse_token_response(response.body)
      rescue Common::Client::Errors::ClientError => e
        raise_client_error(e, 'Token')
      end

      def user_info(access_token)
        auth_header = { 'Authorization' => "Bearer #{access_token}" }
        response = perform(:get, userinfo_path(access_token), userinfo_params, auth_header)

        parse_user_info(response)
      rescue Common::Client::Errors::ClientError => e
        raise_client_error(e, 'UserInfo')
      end

      def jwt_decode(encoded_jwt)
        verify_expiration = true
        decode_options = { algorithm: config.jwt_decode_algorithm, jwks: method(:jwks_loader) }

        JWT.decode(encoded_jwt, nil, verify_expiration, decode_options).first
      rescue JWT::JWKError
        raise Errors::PublicJWKError, "#{config.log_prefix} Public JWK is malformed"
      rescue JWT::VerificationError
        raise Errors::JWTVerificationError, "#{config.log_prefix} JWT body does not match signature"
      rescue JWT::ExpiredSignature
        raise Errors::JWTExpiredError, "#{config.log_prefix} JWT has expired"
      rescue JWT::DecodeError
        raise Errors::JWTDecodeError, "#{config.log_prefix} JWT is malformed"
      end

      private

      def default_acr
        raise NotImplementedError, "#{self.class} must implement #default_acr"
      end

      def auth_params(*)
        raise NotImplementedError, "#{self.class} must implement #auth_params"
      end

      def token_params(*)
        raise NotImplementedError, "#{self.class} must implement #token_params"
      end

      def parse_user_info(*)
        raise NotImplementedError, "#{self.class} must implement #parse_user_info"
      end

      def credential_attributes(*)
        raise NotImplementedError, "#{self.class} must implement #credential_attributes"
      end

      def get_authn_context(*)
        raise NotImplementedError, "#{self.class} must implement #get_authn_context"
      end

      def base_attributes(user_info, credential_level)
        {
          current_ial: credential_level.current_ial,
          max_ial: credential_level.max_ial,
          csp_email: user_info.email,
          authn_context: get_authn_context(credential_level.current_ial),
          auto_uplevel: credential_level.auto_uplevel
        }
      end

      def base_auth_params(state)
        {
          client_id: config.client_id,
          redirect_uri: config.redirect_uri,
          response_type: config.response_type,
          state:
        }
      end

      def log_rendering_auth(state:, operation:, **)
        Rails.logger.info("#{config.log_prefix} Rendering auth, state: #{state}, operation: #{operation}")
      end

      def token_success_log(code, _response)
        "#{config.log_prefix} Token Success, code: #{code}"
      end

      def token_content_type
        'application/json'
      end

      def encode_token_params(params)
        if token_content_type == 'application/x-www-form-urlencoded'
          URI.encode_www_form(params)
        else
          params.to_json
        end
      end

      def parse_token_response(response_body)
        response_body
      end

      def userinfo_path(_access_token)
        config.userinfo_path
      end

      def userinfo_params
        nil
      end

      def raise_client_error(client_error, function_name)
        status = client_error.status
        description = error_description(client_error)

        raise client_error, "#{config.log_prefix} Cannot perform #{function_name} request, " \
                            "status: #{status}, description: #{description}"
      end

      def error_description(client_error)
        client_error.body && client_error.body[:error]
      end

      def log_credential(credential)
        MockedAuthentication::Mockdata::Writer.save_credential(credential:, credential_type: config.service_name)
      end

      def valid_optional_scopes(optional_scopes)
        optional_scopes.to_a & self.class::OPTIONAL_SCOPES
      end

      def credential_attributes_digest(attributes, credential_uuid)
        SignIn::CredentialAttributesDigester.new(credential_uuid:,
                                                 first_name: attributes[:first_name],
                                                 last_name: attributes[:last_name],
                                                 ssn: attributes[:ssn],
                                                 birth_date: attributes[:birth_date],
                                                 email: attributes[:csp_email]).perform
      end
    end
  end
end
