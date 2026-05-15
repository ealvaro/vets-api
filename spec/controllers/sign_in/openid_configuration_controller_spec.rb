# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::OpenidConfigurationController, type: :controller do
  describe 'GET show' do
    subject { get(:show) }

    let(:base_url) { IdentitySettings.sign_in.sts_client.base_url }

    it 'returns ok status' do
      expect(subject).to have_http_status(:ok)
    end

    it 'renders the openid configuration' do
      subject
      json_response = JSON.parse(response.body)

      expect(json_response).to eq(
        'issuer' => IdentitySettings.sign_in.oidc_issuer,
        'authorization_endpoint' => "#{base_url}#{SignIn::Constants::Auth::AUTHORIZE_SSO_ROUTE_PATH}",
        'token_endpoint' => "#{base_url}#{SignIn::Constants::Auth::TOKEN_ROUTE_PATH}",
        'userinfo_endpoint' => "#{base_url}#{SignIn::Constants::Auth::USERINFO_ROUTE_PATH}",
        'jwks_uri' => "#{base_url}#{SignIn::Constants::Auth::CERTS_ROUTE_PATH}",
        'revocation_endpoint' => "#{base_url}#{SignIn::Constants::Auth::REVOKE_ROUTE_PATH}",
        'end_session_endpoint' => "#{base_url}#{SignIn::Constants::Auth::LOGOUT_ROUTE_PATH}",
        'scopes_supported' => SignIn::Constants::Auth::SCOPES,
        'response_types_supported' => SignIn::Constants::Auth::RESPONSE_TYPES_SUPPORTED,
        'grant_types_supported' => SignIn::Constants::Auth::GRANT_TYPES,
        'subject_types_supported' => SignIn::Constants::Auth::SUBJECT_TYPES_SUPPORTED,
        'id_token_signing_alg_values_supported' => [SignIn::Constants::AccessToken::JWT_ENCODE_ALGORITHM],
        'token_endpoint_auth_methods_supported' => SignIn::Constants::Auth::TOKEN_ENDPOINT_AUTH_METHODS,
        'token_endpoint_auth_signing_alg_values_supported' => [SignIn::Constants::Auth::ASSERTION_ENCODE_ALGORITHM],
        'code_challenge_methods_supported' => [SignIn::Constants::Auth::CODE_CHALLENGE_METHOD],
        'acr_values_supported' => SignIn::Constants::Auth::ACR_VALUES,
        'claims_supported' => SignIn::Constants::AccessToken::USER_ATTRIBUTES
      )
    end
  end
end
