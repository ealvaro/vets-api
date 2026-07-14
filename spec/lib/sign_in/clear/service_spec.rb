# frozen_string_literal: true

require 'rails_helper'
require 'sign_in/clear/code_container'
require 'sign_in/clear/service'

describe SignIn::Clear::Service do
  subject { described_class.new }

  let(:base_path) { 'https://verified.clearme.com' }
  let(:client_id) { 'ad13f82d-1175-4873-8dd8-6c460419a2f4' }
  let(:state) { 'some-state' }
  let(:code) { 'placeholder-code' }
  let(:verification_id) { 'verify_NLP2jaxJ8EmPW9MlGYXexRw1uUtUEdQf' }

  before do
    allow(IdentitySettings.clear).to receive_messages(oauth_url: base_path, client_id:)
  end

  describe '#render_auth' do
    let(:response) { subject.render_auth(state:).to_s }
    let(:expected_authorization_page) { "#{base_path}/integrations/oauth2/auth" }
    let(:expected_scope) { CGI.escape('offline openid offline_access') }
    let(:expected_log) do
      "[SignIn][Clear][Service] Rendering auth, state: #{state}, operation: #{SignIn::Constants::Auth::AUTHORIZE}"
    end
    let(:code_verifier) { 'some-code-verifier' }
    let(:expected_code_challenge) do
      Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
    end

    before { allow(SecureRandom).to receive(:urlsafe_base64).and_return(code_verifier) }

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

    it 'includes the expected code_challenge' do
      response

      expect(response).to include('code_challenge_method=S256')
      expect(response).to include("code_challenge=#{expected_code_challenge}")
    end

    it 'includes the state param' do
      expect(response).to include("state=#{state}")
    end

    it 'persists a code verifier keyed by state' do
      response
      container = SignIn::Clear::CodeContainer.find(state)

      expect(container).to be_present
      expect(container.code_verifier).to eq(code_verifier)
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
    let(:code_verifier) { 'some-code-verifier' }
    let(:expected_log) { "[SignIn][Clear][Service] Token Success, code: #{code}" }

    before { create(:clear_code_container, state:, code_verifier:) }

    context 'when the request is successful' do
      around { |example| VCR.use_cassette('identity/clear_200_responses') { example.run } }

      it 'logs information to rails logger' do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(expected_log)
        subject.token(code, state)
      end

      it 'returns the access and id tokens' do
        result = subject.token(code, state)

        expect(result.keys).to contain_exactly(:access_token, :id_token)
        expect(JWT.decode(result[:access_token], nil, false).first).to include('verification_id' => verification_id)
        expect(JWT.decode(result[:id_token], nil, false).first).to include('given_name' => 'John')
      end

      it 'makes a request with the expected body' do
        allow(IdentitySettings.clear).to receive(:client_secret).and_return('some-client-secret')

        subject.token(code, state)

        expect(
          a_request(:post, "#{base_path}/integrations/oauth2/token").with(
            body: {
              grant_type: 'authorization_code',
              code:,
              redirect_uri: IdentitySettings.clear.redirect_uri,
              client_id:,
              client_secret: 'some-client-secret',
              code_verifier:
            }
          )
        ).to have_been_made
      end

      it 'consumes the code verifier from redis' do
        subject.token(code, state)

        expect(SignIn::Clear::CodeContainer.find(state)).to be_nil
      end
    end

    context 'when no code verifier exists for the state' do
      let(:expected_error) { SignIn::Clear::Errors::CodeVerifierNotFoundError }
      let(:expected_error_message) { '[SignIn][Clear][Service] Code verifier not found' }

      before { SignIn::Clear::CodeContainer.find(state).destroy }

      it 'raises a code verifier not found error' do
        expect { subject.token(code, state) }.to raise_error(expected_error, expected_error_message)
      end
    end

    context 'when an issue occurs with the client request' do
      let(:expected_error) { Common::Client::Errors::ClientError }
      let(:expected_error_message) do
        "[SignIn][Clear][Service] Cannot perform Token request, status: #{status}, description: #{description}"
      end
      let(:status) { 'some-status' }
      let(:description) { 'some-description' }
      let(:raised_error) { Common::Client::Errors::ClientError.new(nil, status, { error: description }) }

      before do
        allow_any_instance_of(described_class).to receive(:perform).and_raise(raised_error)
      end

      it 'raises a client error with expected message' do
        expect { subject.token(code, state) }.to raise_error(expected_error, expected_error_message)
      end
    end
  end

  describe '#user_info' do
    let(:user_info_request) { a_request(:get, %r{#{base_path}/v1/verification_sessions/}) }

    context 'when the request is successful' do
      around { |example| VCR.use_cassette('identity/clear_200_responses') { example.run } }

      let(:code_verifier) { 'some-code-verifier' }
      let(:access_token) do
        create(:clear_code_container, state:, code_verifier:)
        subject.token(code, state)[:access_token]
      end

      it 'returns the verification session wrapped in an OpenStruct' do
        result = subject.user_info(access_token)

        expect(result.user_id).to eq('nYcNt2sQK1a093iTCctnMedTDHBgEGsoBUw7Sagb0Q')
        expect(result.sub).to eq('nYcNt2sQK1a093iTCctnMedTDHBgEGsoBUw7Sagb0Q')
        expect(result.traits[:first_name]).to eq('John')
        expect(result.traits[:address][:line1]).to eq('123 Test St')
      end
    end

    context 'when the access token is a malformed JWT' do
      let(:access_token) { 'some-malformed-access-token' }
      let(:expected_error) { SignIn::Clear::Errors::JWTDecodeError }
      let(:expected_error_message) { '[SignIn][Clear][Service] Access token is malformed' }

      it 'raises a JWT decode error' do
        expect { subject.user_info(access_token) }
          .to raise_error(expected_error, expected_error_message)
        expect(user_info_request).not_to have_been_made
      end
    end

    context 'when the access token is valid but missing verification_id' do
      let(:access_token) { JWT.encode({ 'sub' => 'clear-user-id' }, nil, 'none') }
      let(:expected_error) { SignIn::Clear::Errors::JWTDecodeError }
      let(:expected_error_message) do
        '[SignIn][Clear][Service] verification_id missing from access token'
      end

      it 'raises a JWT decode error' do
        expect { subject.user_info(access_token) }
          .to raise_error(expected_error, expected_error_message)
        expect(user_info_request).not_to have_been_made
      end
    end

    context 'when an issue occurs with the client request' do
      let(:access_token) { JWT.encode({ 'verification_id' => verification_id }, nil, 'none') }
      let(:expected_error) { Common::Client::Errors::ClientError }
      let(:expected_error_message) do
        "[SignIn][Clear][Service] Cannot perform UserInfo request, status: #{status}, description: #{description}"
      end
      let(:status) { 'some-status' }
      let(:description) { 'some-description' }
      let(:raised_error) { Common::Client::Errors::ClientError.new(nil, status, { error: description }) }

      before do
        allow_any_instance_of(described_class).to receive(:perform).and_raise(raised_error)
      end

      it 'raises a client error with expected message' do
        expect { subject.user_info(access_token) }
          .to raise_error(expected_error, expected_error_message)
      end
    end
  end

  describe '#normalized_attributes' do
    let(:credential_level) { OpenStruct.new(current_ial: 2, max_ial: 2, auto_uplevel: false) }
    let(:address) do
      { line1: '123 Test St', line2: 'Apt. A', city: 'Test City',
        state: 'NY', postal_code: '12345', country: 'USA' }
    end
    let(:dob) { { day: 1, month: 1, year: 1990 } }
    let(:traits) do
      { first_name: 'John', middle_name: 'Mark', last_name: 'Doe', dob:,
        ssn9: '123-45-6789', phone: '+14082222222', email: 'found@clearme.com', address: }
    end
    let(:user_info) do
      OpenStruct.new(user_id: 'nYcNt2sQK1a093iTCctnMedTDHBgEGsoBUw7Sagb0Q',
                     sub: 'nYcNt2sQK1a093iTCctnMedTDHBgEGsoBUw7Sagb0Q',
                     traits:)
    end
    let(:attributes) { subject.normalized_attributes(user_info, credential_level) }

    let(:digest) { 'some-digest' }
    let(:credential_digester) { instance_double(SignIn::CredentialAttributesDigester, perform: digest) }
    let(:expected_attributes) do
      {
        clear_uuid: 'nYcNt2sQK1a093iTCctnMedTDHBgEGsoBUw7Sagb0Q',
        current_ial: 2,
        max_ial: 2,
        ssn: '123456789',
        birth_date: '1990-01-01',
        first_name: 'John',
        middle_name: 'Mark',
        last_name: 'Doe',
        phone_number: '+14082222222',
        address: { street: '123 Test St', street2: 'Apt. A', postal_code: '12345',
                   state: 'NY', city: 'Test City', country: 'USA' },
        csp_email: 'found@clearme.com',
        multifactor: true,
        service_name: 'clear',
        authn_context: SignIn::Constants::Auth::CLEAR_IAL2,
        auto_uplevel: false,
        digest:
      }
    end

    before { allow(SignIn::CredentialAttributesDigester).to receive(:new).and_return(credential_digester) }

    it 'returns the expected attributes from the verification session' do
      expect(attributes).to eq(expected_attributes)
    end

    context 'when the address is blank' do
      let(:address) { nil }

      it 'sets the address to nil' do
        expect(attributes[:address]).to be_nil
      end
    end

    context 'when the address country is not US' do
      let(:address) do
        { line1: '1 Main St', line2: nil, city: 'Toronto', state: 'ON', postal_code: 'M5V', country: 'CA' }
      end

      it 'passes the country code through unchanged' do
        expect(attributes[:address][:country]).to eq('CA')
      end
    end

    context 'when the address country is US' do
      let(:address) do
        { line1: '1 Main St', line2: nil, city: 'Madison', state: 'WI', postal_code: '53711', country: 'US' }
      end

      it 'normalizes the country to USA' do
        expect(attributes[:address][:country]).to eq('USA')
      end
    end

    context 'when the dob is blank' do
      let(:dob) { nil }

      it 'sets the birth_date to nil' do
        expect(attributes[:birth_date]).to be_nil
      end
    end

    context 'when the dob has a single-digit month and day' do
      let(:dob) { { day: 5, month: 3, year: 2001 } }

      it 'zero-pads the birth_date' do
        expect(attributes[:birth_date]).to eq('2001-03-05')
      end
    end
  end
end
