# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::AuthorizeSSOController, type: :controller do
  describe 'GET authorize_sso' do
    subject { get(:authorize_sso, params: authorize_sso_params) }

    let(:client_id) { 'some-client-id' }
    let(:client_id_param) { client_id }
    let(:app_name) { 'some-app-name' }
    let(:code_challenge) { Base64.urlsafe_encode64('some-code-challenge') }
    let(:code_challenge_method) { 'S256' }
    let(:private_key) { OpenSSL::PKey::RSA.new(2048) }
    let(:encode_algorithm) { SignIn::Constants::Auth::JWT_ENCODE_ALGORITHM }
    let(:state) { JWT.encode('some-state', private_key, encode_algorithm) }

    let(:authorize_sso_params) do
      {
        client_id: client_id_param,
        app_name:,
        code_challenge:,
        code_challenge_method:,
        state:
      }
    end

    let(:shared_sessions) { true }
    let!(:client_config) do
      create(:client_config, shared_sessions:, json_api_compatibility: false, client_id:, pkce:, auth_method:)
    end
    let(:pkce) { true }
    let(:auth_method) { pkce ? 'pkce' : 'private_key_jwt' }

    let!(:user_account) { create(:user_account) }
    let!(:terms_of_use_agreement) { create(:terms_of_use_agreement, user_account:) }
    let!(:user_verification) { create(:user_verification, user_account:) }

    let!(:existing_session_client_config) do
      create(:client_config, shared_sessions:, authentication: SignIn::Constants::Auth::COOKIE)
    end

    let!(:existing_session) do
      create(:oauth_session,
             client_id: existing_session_client_config.client_id,
             user_verification:,
             user_account:)
    end

    let(:existing_access_token) { create(:access_token, session_handle: existing_session.handle) }
    let(:existing_access_token_cookie) do
      SignIn::AccessTokenJwtEncoder.new(access_token: existing_access_token).perform if existing_access_token
    end

    let(:authorize_sso_id) { SecureRandom.uuid }

    before do
      request.cookies[SignIn::Constants::Auth::ACCESS_TOKEN_COOKIE_NAME] = existing_access_token_cookie
      allow(Rails.logger).to receive(:info)
      allow(StatsD).to receive(:increment)
      allow(SecureRandom).to receive(:uuid).and_return(authorize_sso_id)
    end

    shared_examples 'a redirect to USIP' do
      before do
        allow(Flipper).to receive(:enabled?).with(:identity_auth_sso_enabled).and_return(true)
      end

      let(:expected_redirect_uri) { 'http://localhost:3001/sign-in' }
      let(:expected_query_params) do
        authorize_sso_params.merge(oauth: true, authorize_sso_id:).to_query
      end
      let(:expected_log_message) { '[SignInService] [V0::SignInController] authorize sso redirect' }
      let(:expected_log_payload) do
        {
          errors: expected_error_message,
          error_code:,
          client_id: client_id_param,
          app_name:
        }
      end
      let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }
      let(:expected_statsd_tags) { ["client_id:#{client_id_param}"] }

      it 'stashes the request params, logs, and redirects to USIP' do
        expect(subject).to redirect_to("#{expected_redirect_uri}?#{expected_query_params}")
        expect(Rails.logger).to have_received(:info).with(expected_log_message, expected_log_payload)
        expect(StatsD).to have_received(:increment).with('api.sis.auth_sso.redirect', tags: expected_statsd_tags)

        container = SignIn::AuthorizeSSOContainer.find(authorize_sso_id)
        expect(container).to have_attributes(
          uuid: authorize_sso_id,
          client_id: client_id_param,
          code_challenge:,
          code_challenge_method:,
          client_state: state,
          app_name:
        )
      end
    end

    shared_examples 'an error response' do
      let(:expected_log_message) { '[SignInService] [V0::SignInController] authorize sso error' }
      let(:expected_log_payload) do
        {
          errors: expected_error_message,
          error_code:,
          client_id: client_id_param.to_s,
          app_name:
        }
      end
      let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }
      let(:expected_statsd_tags) { ["client_id:#{client_id_param}"] }
      let(:request_id) { SecureRandom.uuid }
      let(:meta_refresh_tag) { '<meta http-equiv="refresh" content="0;' }

      before do
        allow_any_instance_of(ActionController::TestRequest).to receive(:request_id).and_return(request_id)
      end

      it 'logs and redirects to the sign-in error page' do
        response = subject
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(meta_refresh_tag)
        expect(response.body).to include('/v0/sign_in/error')
        expect(response.body).to include("error_code=#{error_code}")
        expect(response.body).to include("request_id=#{request_id}")
        expect(Rails.logger).to have_received(:info).with(expected_log_message, expected_log_payload)
        expect(StatsD).to have_received(:increment).with('api.sis.auth_sso.failure', tags: expected_statsd_tags)
      end
    end

    context 'when authentication fails' do
      context 'when there is no existing access token' do
        let(:expected_error_message) { 'Access token JWT is malformed' }

        before { request.cookies.clear }

        it_behaves_like 'a redirect to USIP'
      end

      context 'when the access token is expired' do
        let(:existing_access_token) { create(:access_token, expiration_time: 1.day.ago) }
        let(:expected_error_message) { 'Access token has expired' }

        it_behaves_like 'a redirect to USIP'
      end

      context 'when a prompt param is present' do
        let(:authorize_sso_params) { super().merge(prompt:) }
        let(:prompt) { SignIn::Constants::Auth::PROMPT_LOGIN }
        let(:expected_error_message) { 'Access token JWT is malformed' }

        before { request.cookies.clear }

        it_behaves_like 'a redirect to USIP'

        context 'and the prompt param is invalid' do
          let(:prompt) { 'some-prompt' }
          let(:expected_error_message) { 'Invalid params: prompt' }

          it_behaves_like 'an error response'
        end
      end

      context 'when stashing the request params fails validation' do
        let(:client_id_param) { '' }
        let(:expected_error_message) { "Invalid params: Client can't be blank" }

        before do
          request.cookies.clear
          allow(Flipper).to receive(:enabled?).with(:identity_auth_sso_enabled).and_return(true)
        end

        it_behaves_like 'an error response' do
          let(:expected_log_payload) do
            {
              errors: expected_error_message,
              error_code:,
              client_id: client_id_param.to_s,
              app_name:,
              authorize_sso_id:
            }
          end
        end

        it 'does not persist a container' do
          subject
          expect(SignIn::AuthorizeSSOContainer.find(authorize_sso_id)).to be_nil
        end
      end

      context 'when an expired authorize_sso_id is replayed with a failed access token' do
        let(:authorize_sso_params) { { authorize_sso_id: } }
        let(:expected_error_message) { "Invalid params: Client can't be blank" }

        before do
          request.cookies.clear
          allow(Flipper).to receive(:enabled?).with(:identity_auth_sso_enabled).and_return(true)
        end

        it 'does not raise a 500 and renders the sign-in error page' do
          response = subject

          expect(response).to have_http_status(:ok)
          expect(response.body).to include('/v0/sign_in/error')
        end
      end

      context 'when redirecting to USIP and the identity_auth_sso_enabled flag is disabled' do
        before do
          request.cookies.clear
          allow(Flipper).to receive(:enabled?).with(:identity_auth_sso_enabled).and_return(false)
        end

        context 'and the client is an okta client' do
          before do
            allow(IdentitySettings.sign_in).to receive(:okta_client_id).and_return(client_id)
          end

          let(:expected_query_params) { authorize_sso_params.merge(oauth: true).to_query }

          it 'redirects to USIP without stashing a container' do
            expect(subject).to redirect_to("http://localhost:3001/sign-in?#{expected_query_params}")
            expect(SignIn::AuthorizeSSOContainer.find(authorize_sso_id)).to be_nil
          end
        end

        context 'and the client is not an okta client' do
          let(:expected_query_params) { authorize_sso_params.merge(oauth: true, authorize_sso_id:).to_query }

          it 'redirects to USIP and still stashes a container' do
            expect(subject).to redirect_to("http://localhost:3001/sign-in?#{expected_query_params}")
            expect(SignIn::AuthorizeSSOContainer.find(authorize_sso_id)).to have_attributes(client_id:)
          end
        end
      end

      context 'and a container exists for a replayed authorize_sso_id' do
        let(:authorize_sso_params) { { authorize_sso_id: } }
        let!(:authorize_sso_container) do
          create(:authorize_sso_container,
                 uuid: authorize_sso_id,
                 client_id:,
                 code_challenge:,
                 code_challenge_method:,
                 client_state: state,
                 app_name:)
        end

        before do
          request.cookies.clear
          allow(Flipper).to receive(:enabled?).with(:identity_auth_sso_enabled).and_return(false)
        end

        it 'does not consume the container, so a retry can still succeed' do
          subject
          expect(SignIn::AuthorizeSSOContainer.find(authorize_sso_id)).not_to be_nil
        end
      end
    end

    context 'when authentication succeeds' do
      context 'and client_id is not given' do
        let(:client_id_param) { '' }
        let(:expected_error_message) { 'Invalid params: client_id' }

        it_behaves_like 'an error response'
      end

      context 'and the client is configured for pkce authentication' do
        let(:pkce) { true }

        context 'and required pkce params are invalid' do
          context 'when code_challenge is not given' do
            let(:code_challenge) { nil }
            let(:expected_error_message) { 'Invalid params: code_challenge' }

            it_behaves_like 'an error response'
          end

          context 'when code_challenge_method is invalid' do
            let(:code_challenge_method) { 'invalid-method' }
            let(:expected_error_message) { 'Invalid params: code_challenge_method' }

            it_behaves_like 'an error response'
          end
        end

        context 'and required params are valid' do
          context 'and there is a downstream error' do
            context 'when the session is not found' do
              let(:expected_error_message) { 'Session not authorized' }

              before do
                allow(SignIn::AuthSSO::SessionValidator).to receive(:new)
                  .and_raise(SignIn::Errors::SessionNotFoundError.new(message: expected_error_message))
              end

              it_behaves_like 'a redirect to USIP'
            end

            context 'when the client_configs are not valid' do
              let(:expected_error_message) { 'SSO requested for client without shared sessions' }
              let(:shared_sessions) { false }

              it_behaves_like 'a redirect to USIP'
            end

            context 'when there is a general error' do
              let(:expected_error_message) { 'An error occurred' }

              before do
                allow(SignIn::AuthSSO::SessionValidator).to receive(:new)
                  .and_raise(StandardError.new(expected_error_message))
              end

              it_behaves_like 'a redirect to USIP'
            end
          end

          context 'and there are no errors' do
            it 'renders an html response with a redirect to the client' do
              response = subject
              expect(response).to have_http_status(:found)
              expect(response.content_type).to eq('text/html; charset=utf-8')
              expect(response.body).to include("URL=#{client_config.redirect_uri}")
              expect(response.body).to include('code=')
              expect(response.body).to include("state=#{state}")
              expect(StatsD).to have_received(:increment).with('api.sis.auth_sso.success',
                                                               tags: ["client_id:#{client_id}"])
            end
          end

          context 'and prompt param is login' do
            let(:authorize_sso_params) { super().merge(prompt: SignIn::Constants::Auth::PROMPT_LOGIN) }
            let(:expected_query_params) { authorize_sso_params.merge(oauth: true, authorize_sso_id:).to_query }

            it 'redirects to USIP instead of issuing a login code' do
              expect(subject).to redirect_to("http://localhost:3001/sign-in?#{expected_query_params}")
              expect(Rails.logger).to have_received(:info).with(
                '[SignInService] [V0::SignInController] authorize sso prompt login redirect',
                { client_id:, app_name: }
              )
              expect(StatsD).to have_received(:increment).with('api.sis.auth_sso.redirect',
                                                               tags: ["client_id:#{client_id}"])
              expect(SignIn::AuthorizeSSOContainer.find(authorize_sso_id)).to have_attributes(client_id:)
            end

            it 'does not invoke the session validator' do
              expect(SignIn::AuthSSO::SessionValidator).not_to receive(:new)
              subject
            end
          end

          context 'and prompt param is invalid' do
            let(:authorize_sso_params) { super().merge(prompt: 'some-prompt') }
            let(:expected_error_message) { 'Invalid params: prompt' }

            it_behaves_like 'an error response'
          end
        end
      end

      context 'and the client is not configured for pkce authentication' do
        let(:pkce) { false }
        let(:auth_method) { 'private_key_jwt' }
        let(:code_challenge) { nil }
        let(:code_challenge_method) { nil }

        context 'and required params are valid' do
          context 'and there are no errors' do
            it 'does not require a code challenge' do
              response = subject

              expect(response).to have_http_status(:found)
              expect(response.body).to include("URL=#{client_config.redirect_uri}")
              expect(response.body).to include('code=')
            end
          end
        end
      end

      context 'and authorize_sso_id is present' do
        let(:authorize_sso_params) { { authorize_sso_id: } }

        context 'and the container exists' do
          let!(:authorize_sso_container) do
            create(:authorize_sso_container,
                   uuid: authorize_sso_id,
                   client_id:,
                   code_challenge:,
                   code_challenge_method:,
                   client_state: state,
                   app_name:)
          end

          it 'uses the container values to issue the login code' do
            response = subject

            expect(response).to have_http_status(:found)
            expect(response.body).to include("URL=#{client_config.redirect_uri}")
            expect(response.body).to include('code=')
            expect(response.body).to include("state=#{state}")
          end

          it 'destroys the container on success' do
            subject
            expect(SignIn::AuthorizeSSOContainer.find(authorize_sso_id)).to be_nil
          end
        end

        context 'and the container is missing' do
          let(:expected_error_message) { 'Invalid params: client_id' }
          let(:client_id_param) { '' }

          it_behaves_like 'an error response' do
            let(:expected_statsd_tags) { ['client_id:'] }
            let(:expected_log_payload) do
              {
                errors: expected_error_message,
                error_code:,
                authorize_sso_id:
              }
            end
          end

          it 'does not invoke the user code map creator' do
            expect(SignIn::AuthSSO::SessionValidator).not_to receive(:new)
            subject
          end

          it 'logs that the authorize sso request was not found or expired' do
            subject
            expect(Rails.logger).to have_received(:info).with(
              '[SignInService] [V0::SignInController] authorize sso request not found or expired',
              { authorize_sso_id: }
            )
          end
        end
      end
    end
  end
end
