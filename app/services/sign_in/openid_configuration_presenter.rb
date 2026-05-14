# frozen_string_literal: true

module SignIn
  class OpenidConfigurationPresenter
    def perform
      {
        issuer: Constants::AccessToken::ISSUER,
        authorization_endpoint: "#{base_url}#{Constants::Auth::AUTHORIZE_SSO_ROUTE_PATH}",
        token_endpoint: "#{base_url}#{Constants::Auth::TOKEN_ROUTE_PATH}",
        userinfo_endpoint: "#{base_url}#{Constants::Auth::USERINFO_ROUTE_PATH}",
        jwks_uri: "#{base_url}#{Constants::Auth::CERTS_ROUTE_PATH}",
        revocation_endpoint: "#{base_url}#{Constants::Auth::REVOKE_ROUTE_PATH}",
        end_session_endpoint: "#{base_url}#{Constants::Auth::LOGOUT_ROUTE_PATH}",
        scopes_supported: Constants::Auth::SCOPES,
        response_types_supported: Constants::Auth::RESPONSE_TYPES_SUPPORTED,
        grant_types_supported: Constants::Auth::GRANT_TYPES,
        subject_types_supported: Constants::Auth::SUBJECT_TYPES_SUPPORTED,
        id_token_signing_alg_values_supported: [Constants::AccessToken::JWT_ENCODE_ALGORITHM],
        token_endpoint_auth_methods_supported: Constants::Auth::TOKEN_ENDPOINT_AUTH_METHODS,
        token_endpoint_auth_signing_alg_values_supported: [Constants::Auth::ASSERTION_ENCODE_ALGORITHM],
        code_challenge_methods_supported: [Constants::Auth::CODE_CHALLENGE_METHOD],
        acr_values_supported: Constants::Auth::ACR_VALUES,
        claims_supported: Constants::AccessToken::USER_ATTRIBUTES
      }
    end

    private

    def base_url
      IdentitySettings.sign_in.sts_client.base_url
    end
  end
end
