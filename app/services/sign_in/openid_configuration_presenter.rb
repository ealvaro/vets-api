# frozen_string_literal: true

module SignIn
  class OpenidConfigurationPresenter
    def perform
      {
        issuer:,
        authorization_endpoint:,
        token_endpoint:,
        userinfo_endpoint:,
        jwks_uri:,
        revocation_endpoint:,
        end_session_endpoint:,
        scopes_supported:,
        response_types_supported:,
        grant_types_supported:,
        subject_types_supported:,
        id_token_signing_alg_values_supported:,
        token_endpoint_auth_methods_supported:,
        token_endpoint_auth_signing_alg_values_supported:,
        code_challenge_methods_supported:,
        acr_values_supported:,
        claims_supported:
      }
    end

    private

    def issuer                                           = IdentitySettings.sign_in.oidc_issuer
    def authorization_endpoint                           = url(Constants::Auth::AUTHORIZE_SSO_ROUTE_PATH)
    def token_endpoint                                   = url(Constants::Auth::TOKEN_ROUTE_PATH)
    def userinfo_endpoint                                = url(Constants::Auth::USERINFO_ROUTE_PATH)
    def jwks_uri                                         = url(Constants::Auth::CERTS_ROUTE_PATH)
    def revocation_endpoint                              = url(Constants::Auth::REVOKE_ROUTE_PATH)
    def end_session_endpoint                             = url(Constants::Auth::LOGOUT_ROUTE_PATH)
    def scopes_supported                                 = Constants::Auth::SCOPES
    def response_types_supported                         = Constants::Auth::RESPONSE_TYPES_SUPPORTED
    def grant_types_supported                            = Constants::Auth::GRANT_TYPES
    def subject_types_supported                          = Constants::Auth::SUBJECT_TYPES_SUPPORTED
    def id_token_signing_alg_values_supported            = [Constants::AccessToken::JWT_ENCODE_ALGORITHM]
    def token_endpoint_auth_methods_supported            = Constants::Auth::TOKEN_ENDPOINT_AUTH_METHODS
    def token_endpoint_auth_signing_alg_values_supported = [Constants::Auth::ASSERTION_ENCODE_ALGORITHM]
    def code_challenge_methods_supported                 = [Constants::Auth::CODE_CHALLENGE_METHOD]
    def acr_values_supported                             = Constants::Auth::ACR_VALUES
    def claims_supported                                 = Constants::AccessToken::USER_ATTRIBUTES

    def url(path)
      "#{IdentitySettings.sign_in.sts_client.base_url}#{path}"
    end
  end
end
