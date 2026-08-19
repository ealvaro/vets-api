# frozen_string_literal: true

require 'rails_helper'
require 'sign_in/entra/service'

describe SignIn::Entra::Service do
  subject { described_class.new }

  let(:oauth_url) { 'https://login.microsoftonline.com' }
  let(:tenant_id) { 'e95f1b23-abaf-45ee-821d-b7ab251ab3bf' }
  let(:base_path) { "#{oauth_url}/#{tenant_id}" }
  let(:client_id) { '3f7019bf-4510-4a2d-a782-ae0b6b119e9d' }
  let(:state) { 'some-state' }
  let(:code) { 'some-code' }
  let(:user_uuid) { 'AAAAAAAAAAAAAAAAAAAAAB1cXk5PWG3fT2xQhZs1FMo' }
  let(:icn) { '1012667145V762142' }
  let(:secid) { '0000028007' }
  let(:current_time) { 1_784_563_200 }

  before do
    allow(IdentitySettings.entra).to receive_messages(oauth_url:, tenant_id:, client_id:)
  end

  describe '#render_auth' do
    let(:response) { subject.render_auth(state:).to_s }
    let(:expected_authorization_page) { "#{base_path}/oauth2/v2.0/authorize" }
    let(:expected_scope) { CGI.escape('openid profile email offline_access') }
    let(:expected_log) do
      "[SignIn][Entra][Service] Rendering auth, state: #{state}, operation: #{SignIn::Constants::Auth::AUTHORIZE}"
    end

    it 'logs information to rails logger' do
      expect(Rails.logger).to receive(:info).with(expected_log)
      response
    end

    it 'renders the expected redirect uri' do
      expect(response).to include(expected_authorization_page)
    end

    it 'includes the client_id, response_type, and scope params' do
      expect(response).to include("client_id=#{client_id}")
      expect(response).to include('response_type=code')
      expect(response).to include("scope=#{expected_scope}")
    end

    it 'includes the prompt param' do
      expect(response).to include('prompt=select_account')
    end

    it 'includes the state param' do
      expect(response).to include("state=#{state}")
    end

    context 'when review_instance_slug is present' do
      let(:review_instance_slug) { 'some-review-instance-slug' }

      before { allow(Settings).to receive(:review_instance_slug).and_return(review_instance_slug) }

      it 'renders the review instance callback proxy as redirect uri' do
        expect(response).to include(
          CGI.escape("https://staging-api.va.gov/#{SignIn::Constants::Auth::REVIEW_INSTANCE_CALLBACK_PROXY_PATH}")
        )
      end
    end
  end

  describe '#token' do
    let(:expected_log) { "[SignIn][Entra][Service] Token Success, code: #{code}" }
    let(:jti) { 'some-jti' }

    before do
      Timecop.freeze(Time.zone.at(current_time))
      allow(SecureRandom).to receive(:hex).and_return(jti)
    end

    after { Timecop.return }

    context 'when the request is successful' do
      let(:client_key) { OpenSSL::PKey::RSA.new(File.read(IdentitySettings.entra.client_key_path)) }
      let(:client_cert) { OpenSSL::X509::Certificate.new(File.read(IdentitySettings.entra.client_cert_path)) }
      let(:client_cert_thumbprint) do
        Base64.urlsafe_encode64(OpenSSL::Digest::SHA1.digest(client_cert.to_der), padding: false)
      end
      let(:expected_assertion_payload) do
        {
          iss: client_id,
          sub: client_id,
          aud: "#{base_path}/oauth2/v2.0/token",
          jti:,
          exp: current_time + 1000
        }
      end
      let(:expected_client_assertion) do
        JWT.encode(expected_assertion_payload, client_key, 'RS256', { x5t: client_cert_thumbprint })
      end

      it 'logs information to rails logger', vcr: { cassette_name: 'identity/entra_200_responses' } do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(expected_log)
        subject.token(code)
      end

      it 'returns the id token as the access token', vcr: { cassette_name: 'identity/entra_200_responses' } do
        result = subject.token(code)
        decoded_token = JWT.decode(result[:access_token], nil, false).first

        expect(result.keys).to contain_exactly(:access_token)
        expect(decoded_token).to include('preferred_username' => 'john.doe@va.gov')
      end

      it 'makes a form urlencoded request with the expected body',
         vcr: { cassette_name: 'identity/entra_200_responses' } do
        subject.token(code)

        expect(
          a_request(:post, "#{base_path}/oauth2/v2.0/token").with(
            body: {
              grant_type: 'authorization_code',
              code:,
              client_id:,
              redirect_uri: IdentitySettings.entra.redirect_uri,
              scope: 'openid profile email offline_access',
              client_assertion_type: 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
              client_assertion: expected_client_assertion
            },
            headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
          )
        ).to have_been_made
      end

      it 'includes a client assertion signed with the client key and cert thumbprint',
         vcr: { cassette_name: 'identity/entra_200_responses' } do
        subject.token(code)

        expect(
          a_request(:post, "#{base_path}/oauth2/v2.0/token").with do |req|
            client_assertion = Rack::Utils.parse_query(req.body)['client_assertion']
            payload, header = JWT.decode(client_assertion, client_key.public_key, true, algorithm: 'RS256')

            payload == expected_assertion_payload.stringify_keys && header['x5t'] == client_cert_thumbprint
          end
        ).to have_been_made
      end
    end

    context 'when an issue occurs with the client request' do
      let(:expected_error) { Common::Client::Errors::ClientError }
      let(:expected_error_message) do
        "[SignIn][Entra][Service] Cannot perform Token request, status: #{status}, description: #{description}"
      end
      let(:status) { 'some-status' }
      let(:description) { 'some-description' }
      let(:raised_error) { Common::Client::Errors::ClientError.new(nil, status, { error: description }) }

      before do
        allow_any_instance_of(described_class).to receive(:perform).and_raise(raised_error)
      end

      it 'raises a client error with expected message' do
        expect { subject.token(code) }.to raise_error(expected_error, expected_error_message)
      end
    end
  end

  describe '#user_info' do
    before { Timecop.freeze(Time.zone.at(current_time)) }

    after { Timecop.return }

    context 'when the id token is valid' do
      let(:id_token) { subject.token(code)[:access_token] }
      let(:expected_jwks_fetch_log) { '[SignIn][Entra][Service] Get Public JWKs Success' }

      it 'fetches the public jwks to verify the id token signature',
         vcr: { cassette_name: 'identity/entra_200_responses' } do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(expected_jwks_fetch_log)

        subject.user_info(id_token)
      end

      it 'returns the id token claims as a normalized user info object',
         vcr: { cassette_name: 'identity/entra_200_responses' } do
        result = subject.user_info(id_token)

        expect(result).to be_a(SignIn::OAuth::UserInfo)
        expect(result).to have_attributes(
          sub: user_uuid,
          email: 'john.doe@va.gov',
          first_name: 'John',
          last_name: 'Doe',
          icn:,
          secid:,
          multifactor: true
        )
      end
    end

    context 'when the id token is malformed' do
      let(:id_token) { 'some-malformed-id-token' }
      let(:expected_error) { SignIn::OAuth::Errors::JWTDecodeError }
      let(:expected_error_message) { '[SignIn][Entra][Service] JWT is malformed' }

      it 'raises a jwt decode error' do
        expect { subject.user_info(id_token) }.to raise_error(expected_error, expected_error_message)
      end
    end

    context 'when the id token is expired' do
      let(:id_token) { subject.token(code)[:access_token] }
      let(:expected_error) { SignIn::OAuth::Errors::JWTExpiredError }
      let(:expected_error_message) { '[SignIn][Entra][Service] JWT has expired' }

      it 'raises a jwt expired error', vcr: { cassette_name: 'identity/entra_200_responses' } do
        expired_id_token = id_token
        Timecop.freeze(Time.zone.at(current_time + 1.day.to_i))

        expect { subject.user_info(expired_id_token) }.to raise_error(expected_error, expected_error_message)
      end
    end
  end

  describe '#normalized_attributes' do
    let(:credential_level) { OpenStruct.new(current_ial: 2, max_ial: 2, auto_uplevel: false) }
    let(:user_info) do
      SignIn::OAuth::UserInfo.new(
        sub: user_uuid,
        email: 'john.doe@va.gov',
        first_name: 'John',
        last_name: 'Doe',
        icn:,
        secid:,
        multifactor: true
      )
    end
    let(:attributes) { subject.normalized_attributes(user_info, credential_level) }

    let(:expected_attributes) do
      {
        entra_uuid: user_uuid,
        current_ial: 2,
        max_ial: 2,
        first_name: 'John',
        last_name: 'Doe',
        icn:,
        secid:,
        csp_email: 'john.doe@va.gov',
        multifactor: true,
        service_name: 'entra',
        authn_context: SignIn::Constants::Auth::ENTRA_IAL2,
        auto_uplevel: false
      }
    end

    it 'returns the expected attributes from the id token claims' do
      expect(attributes).to eq(expected_attributes)
    end

    it 'does not digest the credential attributes' do
      expect(SignIn::CredentialAttributesDigester).not_to receive(:new)

      attributes
    end
  end
end
