# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::OpenidConfigurationPresenter do
  describe '#perform' do
    subject { SignIn::OpenidConfigurationPresenter.new.perform }

    let(:base_url) { IdentitySettings.sign_in.sts_client.base_url }

    it 'returns the expected issuer' do
      expect(subject[:issuer]).to eq(IdentitySettings.sign_in.oidc_issuer)
    end

    it 'returns the expected authorization_endpoint' do
      expect(subject[:authorization_endpoint]).to eq("#{base_url}#{SignIn::Constants::Auth::AUTHORIZE_SSO_ROUTE_PATH}")
    end

    it 'returns the expected token_endpoint' do
      expect(subject[:token_endpoint]).to eq("#{base_url}#{SignIn::Constants::Auth::TOKEN_ROUTE_PATH}")
    end

    it 'returns the expected userinfo_endpoint' do
      expect(subject[:userinfo_endpoint]).to eq("#{base_url}#{SignIn::Constants::Auth::USERINFO_ROUTE_PATH}")
    end

    it 'returns the expected jwks_uri' do
      expect(subject[:jwks_uri]).to eq("#{base_url}#{SignIn::Constants::Auth::CERTS_ROUTE_PATH}")
    end

    it 'returns the expected revocation_endpoint' do
      expect(subject[:revocation_endpoint]).to eq("#{base_url}#{SignIn::Constants::Auth::REVOKE_ROUTE_PATH}")
    end

    it 'returns the expected end_session_endpoint' do
      expect(subject[:end_session_endpoint]).to eq("#{base_url}#{SignIn::Constants::Auth::LOGOUT_ROUTE_PATH}")
    end

    it 'returns the expected scopes_supported' do
      expect(subject[:scopes_supported]).to eq(SignIn::Constants::Auth::SCOPES)
    end

    it 'returns the expected response_types_supported' do
      expect(subject[:response_types_supported]).to eq(SignIn::Constants::Auth::RESPONSE_TYPES_SUPPORTED)
    end

    it 'returns the expected grant_types_supported' do
      expect(subject[:grant_types_supported]).to eq(SignIn::Constants::Auth::GRANT_TYPES)
    end

    it 'returns the expected subject_types_supported' do
      expect(subject[:subject_types_supported]).to eq(SignIn::Constants::Auth::SUBJECT_TYPES_SUPPORTED)
    end

    it 'returns the expected id_token_signing_alg_values_supported' do
      expect(subject[:id_token_signing_alg_values_supported]).to eq([SignIn::Constants::AccessToken::JWT_ENCODE_ALGORITHM])
    end

    it 'returns the expected token_endpoint_auth_methods_supported' do
      expect(subject[:token_endpoint_auth_methods_supported]).to eq(SignIn::Constants::Auth::TOKEN_ENDPOINT_AUTH_METHODS)
    end

    it 'includes client_secret_basic in token_endpoint_auth_methods_supported' do
      expect(subject[:token_endpoint_auth_methods_supported]).to include('client_secret_basic')
    end

    it 'returns the expected token_endpoint_auth_signing_alg_values_supported' do
      expect(subject[:token_endpoint_auth_signing_alg_values_supported]).to eq([SignIn::Constants::Auth::ASSERTION_ENCODE_ALGORITHM])
    end

    it 'returns the expected code_challenge_methods_supported' do
      expect(subject[:code_challenge_methods_supported]).to eq([SignIn::Constants::Auth::CODE_CHALLENGE_METHOD])
    end

    it 'returns the expected acr_values_supported' do
      expect(subject[:acr_values_supported]).to eq(SignIn::Constants::Auth::ACR_VALUES)
    end

    it 'returns the expected claims_supported' do
      expect(subject[:claims_supported]).to eq(SignIn::Constants::AccessToken::USER_ATTRIBUTES)
    end
  end
end
