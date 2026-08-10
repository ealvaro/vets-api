# frozen_string_literal: true

require 'sign_in/entra/configuration'
require 'sign_in/oauth/service'

module SignIn
  module Entra
    class Service < SignIn::OAuth::Service
      configuration Configuration

      def user_info(id_token)
        claims = jwt_decode(id_token)
        log_credential(claims) if config.log_credential

        build_user_info(claims)
      end

      private

      def default_acr
        OAuth::Constants::ENTRA_IAL2
      end

      def auth_params(_acr, state, _operation, **)
        base_auth_params(state).merge(
          scope: config.scope,
          prompt: config.prompt
        )
      end

      def token_params(code, *)
        {
          grant_type: config.grant_type,
          code:,
          client_id: config.client_id,
          redirect_uri: config.redirect_uri,
          scope: config.scope,
          client_assertion_type: config.client_assertion_type,
          client_assertion: client_assertion_jwt
        }
      end

      def token_content_type
        'application/x-www-form-urlencoded'
      end

      def parse_token_response(response_body)
        { access_token: response_body[:access_token], id_token: response_body[:id_token] }
      end

      def build_user_info(claims)
        info = claims.with_indifferent_access

        OAuth::UserInfo.new(
          sub: info[:sub],
          email: info[:email],
          first_name: info[:given_name],
          last_name: info[:family_name],
          icn: info[:icn],
          secid: info[:secid],
          multifactor: true
        )
      end

      def credential_attributes(user_info)
        {
          entra_uuid: user_info.sub,
          first_name: user_info.first_name,
          last_name: user_info.last_name,
          icn: user_info.icn,
          secid: user_info.secid,
          multifactor: user_info.multifactor,
          service_name: config.service_name
        }
      end

      def get_authn_context(_current_ial)
        OAuth::Constants::ENTRA_IAL2
      end

      def client_assertion_jwt
        jwt_payload = {
          iss: config.client_id,
          sub: config.client_id,
          aud: config.token_url,
          jti: SecureRandom.hex,
          exp: Time.now.to_i + config.client_assertion_expiration_seconds
        }
        JWT.encode(jwt_payload, config.ssl_key, 'RS256', { x5t: config.client_cert_thumbprint })
      end
    end
  end
end
