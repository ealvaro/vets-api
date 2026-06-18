# frozen_string_literal: true

require 'rails_helper'

describe SignIn::UserInfoController do
  let!(:client_config) { create(:client_config, client_id:, oidc:) }
  let(:client_id) { 'some-client-id' }
  let(:user_info_clients) { [client_id] }
  let(:oidc) { false }
  let!(:session) { create(:oauth_session, client_id:, user_account:, user_verification:) }

  let(:user_account) { create(:user_account, icn:) }
  let(:user_verification) { create(:idme_user_verification, idme_uuid: credential_uuid, user_account:) }
  let(:mpi_profile) do
    build(:mpi_profile, icn:, address:, home_phone:, full_mvi_ids: gcids)
  end

  let(:user) do
    build(
      :user,
      :loa3,
      user_account:,
      user_verification:,
      icn:,
      idme_uuid: credential_uuid,
      first_name: mpi_profile.given_names.first,
      last_name: mpi_profile.family_name,
      birth_date: mpi_profile.birth_date,
      ssn: mpi_profile.ssn,
      gender: mpi_profile.gender,
      edipi: mpi_profile.edipi,
      sec_id: mpi_profile.sec_id,
      mpi_profile:
    )
  end
  let(:credential_uuid) { 'some-uuid' }
  let(:icn) { 'some-icn' }

  let(:home_phone) { '555-123-4567' }
  let(:gcids) do
    [
      '1000123456V123456^NI^200M^USVHA^P',
      '12345^PI^516^USVHA^PCE',
      '2^PI^553^USVHA^PCE'
    ]
  end

  let(:address) do
    {
      street: '123 Main St',
      street2: 'Apt 4B',
      city: 'Somecity',
      state: 'CA',
      country: 'USA',
      postal_code: '90210'
    }
  end

  let!(:user_credential_email) { create(:user_credential_email, user_verification:, credential_email:) }
  let(:credential_email) { 'test@example.com' }

  let(:access_token) { create(:access_token, user_uuid: user.uuid, client_id:, session_handle: session.handle) }
  let(:encoded_access_token) { SignIn::AccessTokenJwtEncoder.new(access_token:).perform }

  before do
    allow(IdentitySettings.sign_in).to receive(:user_info_clients).and_return(user_info_clients)
    request.headers['Authorization'] = "Bearer #{encoded_access_token}"
  end

  describe 'GET #show' do
    context 'when the client_id is in the list of valid clients' do
      context 'when the user has valid attributes' do
        context 'when the client is not oidc' do
          let(:expected_response_body) do
            {
              sub: credential_uuid,
              ial: SignIn::Constants::Auth::IAL_TWO.to_s,
              aal: 'http://idmanagement.gov/ns/assurance/aal/2',
              csp_type: MPI::Constants::IDME_IDENTIFIER,
              csp_uuid: credential_uuid,
              email: credential_email,
              first_name: user.first_name,
              middle_name: user.middle_name,
              last_name: user.last_name,
              full_name: user.full_name_normalized.values.compact.join(' '),
              birth_date: user.birth_date,
              ssn: user.ssn,
              gender: user.gender,
              address_street1: user.address[:street],
              address_street2: user.address[:street2],
              address_city: user.address[:city],
              address_state: user.address[:state],
              address_country: user.address[:country],
              address_postal_code: user.address[:postal_code],
              phone_number: user.home_phone,
              person_types: user.person_types.join('|'),
              icn: user.icn,
              edipi: user.edipi,
              mhv_ien: user.mhv_ien,
              sec_id: user.sec_id,
              sec_id_history: user.sec_id_history.join('|'),
              npi_id: user.npi_id,
              cerner_id: user.cerner_id,
              corp_id: user.participant_id,
              birls: user.birls_id,
              gcids: gcids.join('|')
            }
          end

          it 'returns the expected response body' do
            get :show

            expect(response).to have_http_status(:ok)

            expect(JSON.parse(response.body, symbolize_names: true)).to eq(expected_response_body)
          end
        end

        context 'when the client is oidc' do
          let(:oidc) { true }

          let(:expected_formatted_address) do
            <<~ADDRESS.strip
              #{user.address[:street]} #{user.address[:street2]}
              #{user.address[:city]}, #{user.address[:state]} #{user.address[:postal_code]}
              #{user.address[:country]}
            ADDRESS
          end

          let(:expected_address) do
            {
              formatted: expected_formatted_address,
              street_address: "#{user.address[:street]} #{user.address[:street2]}",
              locality: user.address[:city],
              region: user.address[:state],
              postal_code: user.address[:postal_code],
              country: user.address[:country]
            }
          end

          let(:expected_response_body) do
            {
              sub: credential_uuid,
              icn: user.icn,
              name: user.full_name_normalized.values.compact.join(' '),
              given_name: user.first_name,
              middle_name: user.middle_name,
              family_name: user.last_name,
              email: credential_email,
              birthdate: user.birth_date,
              gender: user.gender,
              phone_number: user.home_phone,
              address: expected_address
            }
          end

          it 'returns the oidc serializable hash' do
            get :show

            expect(response).to have_http_status(:ok)

            expect(JSON.parse(response.body, symbolize_names: true)).to eq(expected_response_body)
          end
        end
      end

      context 'when the user_info is invalid' do
        before do
          allow_any_instance_of(SignIn::UserInfo).to receive(:valid?).and_return(false)
        end

        it 'returns a bad request' do
          get :show

          expect(response).to have_http_status(:bad_request)
        end
      end

      context 'when the client_id is not in the list of valid clients' do
        let(:user_info_clients) { ['some-other-client-id'] }

        it 'returns a forbidden response' do
          get :show
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end
end
