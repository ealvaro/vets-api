# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sts::UserCredentialsController, type: :controller do
  let(:service_account_config) { create(:service_account_config, service_account_id: 'identity_dashboard', scopes:) }
  let(:service_account_id) { service_account_config.service_account_id }
  let(:scopes) { ['http://www.example.com/sts/user_credentials'] }
  let(:token_user_attributes) { {} }
  let(:service_account_access_token) do
    create(:service_account_access_token, service_account_id:, scopes:, user_attributes: token_user_attributes)
  end
  let(:sts_token) do
    SignIn::ServiceAccountAccessTokenJwtEncoder.new(service_account_access_token:).perform
  end
  let(:authenticated) { true }
  let(:request_params) { { requested_by: 'some-email@va.gov' } }

  before do
    request.headers['Authorization'] = "Bearer #{sts_token}" if authenticated
  end

  shared_examples 'verification action validations' do
    context 'without an authorization header' do
      let(:authenticated) { false }

      it 'returns 401' do
        perform_verification_request
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a token lacking the required scope' do
      let(:scopes) { ['http://www.example.com/other'] }

      it 'returns 401' do
        perform_verification_request
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when requested_by is missing' do
      let(:request_params) { {} }

      it 'returns 400' do
        perform_verification_request
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when type is missing from token attributes' do
      let(:token_user_attributes) { { 'credential_id' => user_verification.idme_uuid } }

      it 'returns 400' do
        perform_verification_request
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when credential_id is missing from token attributes' do
      let(:token_user_attributes) { { 'type' => 'idme' } }

      it 'returns 400' do
        perform_verification_request
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when user_verification is not found' do
      let(:token_user_attributes) { { 'type' => 'idme', 'credential_id' => 'some-credential_id' } }

      it 'returns 404' do
        perform_verification_request
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  shared_examples 'account action validations' do
    context 'without an authorization header' do
      let(:authenticated) { false }

      it 'returns 401' do
        perform_account_request
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a token lacking the required scope' do
      let(:scopes) { ['https://api.va.gov/some-scope'] }

      it 'returns 401' do
        perform_account_request
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when requested_by is missing' do
      let(:request_params) { {} }

      it 'returns 400' do
        perform_account_request
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when icn is missing from token attributes' do
      let(:token_user_attributes) { {} }

      it 'returns 400' do
        perform_account_request
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when icn is not found' do
      let(:token_user_attributes) { { 'icn' => 'some-icn' } }

      it 'returns 404' do
        perform_account_request
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'verification actions' do
    let(:user_verification) { create(:idme_user_verification) }
    let(:token_user_attributes) { { 'type' => 'idme', 'credential_id' => user_verification.idme_uuid } }

    describe 'POST #lock_verification' do
      subject(:perform_verification_request) { post :lock_verification, params: request_params }

      include_examples 'verification action validations'

      context 'with valid verification credentials' do
        it 'locks the user_verification and returns 200' do
          perform_verification_request
          expect(response).to have_http_status(:ok)
          expect(user_verification.reload.locked).to be(true)
        end
      end
    end

    describe 'POST #unlock_verification' do
      subject(:perform_verification_request) { post :unlock_verification, params: request_params }

      let(:user_verification) { create(:idme_user_verification, locked: true) }

      include_examples 'verification action validations'

      context 'with valid verification credentials' do
        it 'unlocks the user_verification and returns 200' do
          perform_verification_request
          expect(response).to have_http_status(:ok)
          expect(user_verification.reload.locked).to be(false)
        end
      end
    end
  end

  describe 'account actions' do
    let(:user_account) { create(:user_account) }
    let(:token_user_attributes) { { 'icn' => user_account.icn } }

    describe 'POST #lock_account' do
      subject(:perform_account_request) { post :lock_account, params: request_params }

      include_examples 'account action validations'

      context 'with valid account credentials' do
        it 'locks the user_account and returns 200' do
          perform_account_request
          expect(response).to have_http_status(:ok)
          expect(user_account.reload.locked).to be(true)
        end
      end
    end

    describe 'POST #unlock_account' do
      subject(:perform_account_request) { post :unlock_account, params: request_params }

      let(:user_account) { create(:user_account, locked: true) }

      include_examples 'account action validations'

      context 'with valid account credentials' do
        it 'unlocks the user_account and returns 200' do
          perform_account_request
          expect(response).to have_http_status(:ok)
          expect(user_account.reload.locked).to be(false)
        end
      end
    end
  end
end
