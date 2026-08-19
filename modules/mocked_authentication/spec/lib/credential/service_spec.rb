# frozen_string_literal: true

require 'rails_helper'
require 'credential/service'

describe MockedAuthentication::Credential::Service do
  let(:mock_credential_instance) { described_class.new }
  let(:type) { 'some-type' }

  before { mock_credential_instance.type = type }

  describe '#render_auth' do
    subject { mock_credential_instance.render_auth(state:, acr:, operation:) }

    let(:state) { 'some-state' }
    let(:acr) { 'some-acr' }
    let(:type) { 'some-type' }
    let(:operation) { 'some-operation' }
    let(:expected_redirect_url) { IdentitySettings.sign_in.mock_auth_url }

    it 'returns the mock authorization url' do
      expect(subject.to_s).to start_with("#{expected_redirect_url}?")
    end

    it 'renders state value' do
      expect(subject.to_s).to include(state)
    end

    it 'renders acr value' do
      expect(subject.to_s).to include(acr)
    end

    it 'renders type value' do
      expect(subject.to_s).to include(type)
    end

    it 'renders operation value' do
      expect(subject.to_s).to include(operation)
    end

    context 'when operation is not supplied' do
      let(:operation) { '' }

      it 'defaults to authorize' do
        expect(subject.to_s).to include(operation)
      end
    end

    it 'directs to the Mocked Authorization frontend page' do
      expect(subject.to_s).to include(expected_redirect_url)
    end
  end

  describe '#token' do
    subject { mock_credential_instance.token(code) }

    let(:code) { 'some-code' }

    context 'when type in mock credential service is set to logingov' do
      let(:type) { SignIn::Constants::Auth::LOGINGOV }
      let(:access_token_hash) { { access_token: code } }
      let(:encoded_credential_info) { Base64.encode64(credential_info.to_json) }
      let(:code) { 'some-code' }

      before do
        allow(SecureRandom).to receive(:hex).and_return(code)
        MockedAuthentication::CredentialInfoCreator.new(credential_info: encoded_credential_info).perform
      end

      context 'and stored logingov credential has ssn attribute' do
        let(:id_token_payload) { { logingov_acr: IAL::LOGIN_GOV_IAL2 } }
        let(:credential_info) { { social_security_number: 'some-social-security-number' } }

        it 'returns expected access token hash merged with id token hash' do
          expect(subject).to eq(access_token_hash.merge(id_token_payload))
        end
      end

      context 'and stored logingov credential does not have ssn attribute' do
        let(:id_token_payload) { { logingov_acr: IAL::LOGIN_GOV_IAL1 } }
        let(:credential_info) { { attribute: 'some-attribute' } }

        it 'returns expected access token hash merged with id token hash' do
          expect(subject).to eq(access_token_hash.merge(id_token_payload))
        end
      end
    end

    context 'when type in mock credential service is not set to logingov' do
      let(:type) { 'some-type' }
      let(:expected_access_token_hash) { { access_token: code } }

      it 'returns expected access token hash' do
        expect(subject).to eq(expected_access_token_hash)
      end
    end
  end

  describe '#user_info' do
    subject { mock_credential_instance.user_info(token) }

    let(:token) { mock_credential_info.credential_info_code }
    let(:mock_credential_info) { create(:mock_credential_info, credential_info:) }

    context 'when type is logingov' do
      let(:type) { SignIn::Constants::Auth::LOGINGOV }
      let(:credential_info) { { sub: 'some-sub', email: 'some-email', social_security_number: 'some-ssn' } }

      it 'returns user info parsed by the logingov service' do
        expect(subject).to be_a(SignIn::OAuth::UserInfo)
        expect(subject.sub).to eq('some-sub')
        expect(subject.email).to eq('some-email')
        expect(subject.ssn).to eq('somessn')
      end
    end

    context 'when type is idme' do
      let(:type) { SignIn::Constants::Auth::IDME }
      let(:credential_info) { { sub: 'some-sub', email: 'some-email', social: 'some-ssn' } }

      it 'returns user info parsed by the idme service' do
        expect(subject).to be_a(SignIn::OAuth::UserInfo)
        expect(subject.sub).to eq('some-sub')
        expect(subject.email).to eq('some-email')
        expect(subject.ssn).to eq('somessn')
      end
    end

    context 'when type is entra' do
      let(:type) { SignIn::Constants::Auth::ENTRA }
      let(:credential_info) do
        { sub: 'some-sub', email: 'some-email', given_name: 'some-first-name',
          family_name: 'some-last-name', icn: 'some-icn', secid: 'some-secid' }
      end

      it 'returns user info parsed by the entra service' do
        expect(subject).to be_a(SignIn::OAuth::UserInfo)
        expect(subject.sub).to eq('some-sub')
        expect(subject.email).to eq('some-email')
        expect(subject.first_name).to eq('some-first-name')
        expect(subject.last_name).to eq('some-last-name')
        expect(subject.icn).to eq('some-icn')
        expect(subject.secid).to eq('some-secid')
        expect(subject.multifactor).to be(true)
      end
    end
  end

  describe '#normalized_attributes' do
    subject { mock_credential_instance.normalized_attributes(user_info, credential_level) }

    let(:user_info) { 'some-user-info' }
    let(:first_name) { 'some-first-name' }
    let(:middle_name) { 'some-middle-name' }
    let(:last_name) { 'some-last-name' }
    let(:birth_date) { 'some-birth-date' }
    let(:ssn) { 'some-ssn' }
    let(:email) { 'some-email' }
    let(:all_emails) { [email] }
    let(:user_uuid) { 'some-user-uuid' }
    let(:street) { "some-street\nsome-second-line-street" }
    let(:postal_code) { 'some-postal-code' }
    let(:region) { 'some-region' }
    let(:locality) { 'some-locality' }
    let(:iss) { 'some-iss' }
    let(:multifactor) { true }
    let(:credential_level) { create(:credential_level, current_ial: IAL::TWO, max_ial: IAL::TWO) }
    let(:auto_uplevel) { false }
    let(:country) { 'USA' }
    let(:phone) { 'some-phone' }
    let(:phone_number) { 'some-phone' }
    let(:digest) { 'some-digest' }
    let(:digester) { instance_double(SignIn::CredentialAttributesDigester) }

    before do
      allow(SignIn::CredentialAttributesDigester).to receive(:new).and_return(digester)
      allow(digester).to receive(:perform).and_return(digest)
    end

    context 'when type is equal to logingov' do
      let(:type) { SignIn::Constants::Auth::LOGINGOV }
      let(:user_info) do
        SignIn::OAuth::UserInfo.new(
          sub: user_uuid,
          email:,
          all_emails:,
          multifactor:,
          first_name:,
          last_name:,
          ssn:,
          birth_date:,
          address: expected_address,
          verified_at:
        )
      end
      let(:verified_at) { 'some-verified-at' }
      let(:expected_standard_attributes) do
        {
          logingov_uuid: user_uuid,
          current_ial: IAL::TWO,
          max_ial: IAL::TWO,
          service_name: type,
          csp_email: email,
          all_csp_emails: all_emails,
          multifactor:,
          authn_context:,
          auto_uplevel:,
          digest:
        }
      end
      let(:authn_context) { IAL::LOGIN_GOV_IAL2 }
      let(:expected_address) do
        {
          street: street.split("\n").first,
          street2: street.split("\n").last,
          postal_code:,
          state: region,
          city: locality,
          country:
        }
      end
      let(:expected_attributes) do
        expected_standard_attributes.merge({ ssn: ssn.tr('-', ''),
                                             birth_date:,
                                             first_name:,
                                             last_name:,
                                             address: expected_address })
      end

      it 'returns expected attributes' do
        expect(subject).to eq(expected_attributes)
      end
    end

    context 'when type is equal to idme' do
      let(:type) { SignIn::Constants::Auth::IDME }
      let(:user_info) do
        SignIn::OAuth::UserInfo.new(
          sub: user_uuid,
          email:,
          multifactor:,
          first_name:,
          last_name:,
          ssn:,
          birth_date:,
          phone_number: phone,
          address: expected_address,
          level_of_assurance: 3,
          credential_ial: 'classic_loa3'
        )
      end
      let(:authn_context) { LOA::IDME_LOA3 }
      let(:expected_address) do
        {
          street:,
          postal_code:,
          state: region,
          city: locality,
          country:
        }
      end
      let(:expected_attributes) do
        {
          idme_uuid: user_uuid,
          current_ial: IAL::TWO,
          max_ial: IAL::TWO,
          service_name: type,
          csp_email: email,
          all_csp_emails: nil,
          multifactor:,
          authn_context:,
          auto_uplevel:,
          ssn: ssn.tr('-', ''),
          birth_date:,
          first_name:,
          last_name:,
          address: expected_address,
          phone_number:,
          digest:
        }
      end

      it 'returns expected attributes' do
        expect(subject).to eq(expected_attributes)
      end
    end

    context 'when type is equal to entra' do
      let(:type) { SignIn::Constants::Auth::ENTRA }
      let(:user_info) do
        SignIn::OAuth::UserInfo.new(
          sub: user_uuid,
          email:,
          multifactor:,
          first_name:,
          last_name:,
          icn:,
          secid:
        )
      end
      let(:icn) { 'some-icn' }
      let(:secid) { 'some-secid' }
      let(:authn_context) { SignIn::Constants::Auth::ENTRA_IAL2 }
      let(:expected_attributes) do
        {
          entra_uuid: user_uuid,
          current_ial: IAL::TWO,
          max_ial: IAL::TWO,
          service_name: type,
          csp_email: email,
          multifactor:,
          authn_context:,
          auto_uplevel:,
          first_name:,
          last_name:,
          icn:,
          secid:
        }
      end

      it 'returns expected attributes' do
        expect(subject).to eq(expected_attributes)
      end
    end

    context 'when type is equal to mhv' do
      let(:type) { SignIn::Constants::Auth::MHV }
      let(:user_info) do
        SignIn::OAuth::UserInfo.new(
          sub: user_uuid,
          email:,
          multifactor:,
          mhv_credential_uuid:,
          icn: mhv_icn,
          mhv_assurance:,
          level_of_assurance: 3,
          credential_ial: 'classic_loa3'
        )
      end
      let(:mhv_credential_uuid) { 'some-mhv-credential-uuid' }
      let(:mhv_icn) { 'some-mhv-icn' }
      let(:mhv_assurance) { 'some-mhv-assurance' }
      let(:authn_context) { LOA::IDME_MHV_LOA3 }
      let(:expected_attributes) do
        {
          idme_uuid: user_uuid,
          current_ial: IAL::TWO,
          max_ial: IAL::TWO,
          service_name: type,
          csp_email: email,
          all_csp_emails: nil,
          multifactor:,
          authn_context:,
          auto_uplevel:,
          mhv_icn:,
          mhv_credential_uuid:,
          mhv_assurance:,
          digest:
        }
      end

      it 'returns expected attributes' do
        expect(subject).to eq(expected_attributes)
      end
    end
  end
end
