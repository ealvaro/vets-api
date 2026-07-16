# frozen_string_literal: true

require 'rails_helper'
require 'rx/client' # used to stub Rx::Client in tests

RSpec.describe ApplicationController, type: :controller do
  controller do
    attr_reader :payload

    skip_before_action :authenticate, except: %i[test_authentication test_logging]

    JSON_ERROR = {
      'errorCode' => 139, 'developerMessage' => '', 'message' => 'Prescription is not Refillable'
    }.freeze

    def not_authorized
      raise Pundit::NotAuthorizedError
    end

    def unauthorized
      raise Common::Exceptions::Unauthorized
    end

    def routing_error
      raise Common::Exceptions::RoutingError
    end

    def forbidden
      raise Common::Exceptions::Forbidden
    end

    def test_logging
      Rails.logger.info sso_logging_info
    end

    def breakers_outage
      Rx::Configuration.instance.breakers_service.begin_forced_outage!
      client = Rx::Client.new(session: { user_id: 123 })
      client.get_session
    end

    def record_not_found
      raise Common::Exceptions::RecordNotFound, 'some_id'
    end

    def other_error
      raise Common::Exceptions::BackendServiceException, 'RX139'
    end

    def common_error_with_warning
      raise Common::Exceptions::BackendServiceException, 'VAOS_409A'
    end

    def client_connection_failed
      client = Rx::Client.new(session: { user_id: 123 })
      client.get_session
    end

    def test_authentication
      head :ok
    end

    def append_info_to_payload(payload)
      super
      @payload = payload
    end
  end

  before do
    routes.draw do
      get 'test_logging' => 'anonymous#test_logging'
      get 'not_authorized' => 'anonymous#not_authorized'
      get 'unauthorized' => 'anonymous#unauthorized'
      get 'routing_error' => 'anonymous#routing_error'
      get 'forbidden' => 'anonymous#forbidden'
      get 'breakers_outage' => 'anonymous#breakers_outage'
      get 'common_error_with_warning' => 'anonymous#common_error_with_warning'
      get 'record_not_found' => 'anonymous#record_not_found'
      get 'other_error' => 'anonymous#other_error'
      get 'client_connection_failed' => 'anonymous#client_connection_failed'
      get 'test_authentication' => 'anonymous#test_authentication'
    end
  end

  describe 'Datadog tracing' do
    let(:active_span) do
      instance_double(Datadog::Tracing::Span)
    end

    it 'sets error state on spans for handled exceptions' do
      allow(Datadog::Tracing).to receive(:active_span).and_return(active_span)
      expect(active_span).to receive(:set_error).with(Common::Exceptions::BackendServiceException)
      get :common_error_with_warning
    end

    it 'does not set error state on spans for expected exceptions' do
      allow(Datadog::Tracing).to receive(:active_span).and_return(active_span)
      expect(active_span).not_to receive(:set_error)
      get :forbidden
    end
  end

  describe '#clear_saved_form' do
    subject do
      controller.clear_saved_form(form_id)
    end

    let(:user) { create(:user) }

    context 'with a saved form' do
      let!(:in_progress_form) { create(:in_progress_form, user_uuid: user.uuid) }
      let(:form_id) { in_progress_form.form_id }

      context 'without a current user' do
        it 'does not delete the form' do
          subject
          expect(model_exists?(in_progress_form)).to be(true)
        end
      end

      context 'with a current user' do
        before do
          controller.instance_variable_set(:@current_user, user)
        end

        it 'deletes the form' do
          subject
          expect(model_exists?(in_progress_form)).to be(false)
        end
      end
    end

    context 'without a saved form' do
      let(:form_id) { 'foo' }

      before do
        controller.instance_variable_set(:@current_user, user)
      end

      it 'does nothing' do
        subject
      end
    end
  end

  context 'RecordNotFound' do
    subject { JSON.parse(response.body)['errors'].first }

    let(:keys_for_all_env) { %w[title detail code status] }

    context 'with Rails.env.test or Rails.env.development' do
      it 'renders json object with developer attributes' do
        get :record_not_found
        expect(subject.keys).to eq(keys_for_all_env)
      end
    end

    context 'with Rails.env.production' do
      it 'renders json error with production attributes' do
        allow(Rails)
          .to(receive(:env))
          .and_return(ActiveSupport::StringInquirer.new('production'))

        get :record_not_found
        expect(subject.keys)
          .to eq(keys_for_all_env)
      end
    end
  end

  context 'BackendServiceErrorError' do
    subject { JSON.parse(response.body)['errors'].first }

    let(:keys_for_production) { %w[title detail code status] }
    let(:keys_for_development) { keys_for_production + ['meta'] }

    context 'with Rails.env.test or Rails.env.development' do
      it 'renders json object with developer attributes' do
        get :other_error
        expect(subject.keys).to eq(keys_for_production)
      end
    end

    context 'with Rails.env.production' do
      it 'renders json error with production attributes' do
        allow(Rails)
          .to(receive(:env))
          .and_return(ActiveSupport::StringInquirer.new('production'))

        get :other_error
        expect(subject.keys)
          .to eq(keys_for_production)
      end
    end
  end

  context 'ConnectionFailed Error' do
    context 'Pundit::NotAuthorizedError' do
      subject { JSON.parse(response.body)['errors'].first }

      let(:keys_for_all_env) { %w[title detail code status] }

      context 'with Rails.env.test or Rails.env.development' do
        it 'renders json object with developer attributes' do
          get :not_authorized

          expect(response).to have_http_status(:forbidden)
          expect(subject.keys).to eq(keys_for_all_env)
        end
      end

      context 'with Rails.env.production' do
        it 'renders json error with production attributes' do
          allow(Rails)
            .to(receive(:env))
            .and_return(ActiveSupport::StringInquirer.new('production'))

          get :not_authorized
          expect(response).to have_http_status(:forbidden)
          expect(subject.keys)
            .to eq(keys_for_all_env)
        end
      end
    end

    describe 'authorization failure logging (AU-3)' do
      let(:test_remote_ip) { '192.168.1.100' }
      let(:test_request_id) { 'abc-123-def-456' }

      before do
        request.env['REMOTE_ADDR'] = test_remote_ip
        allow(controller).to receive(:request).and_wrap_original do |original|
          req = original.call
          req.request_id = test_request_id
          req
        end
      end

      context 'when a Pundit::NotAuthorizedError is raised' do
        let(:expected_detail) do
          [{ title: 'Forbidden',
             detail: 'User does not have access to the requested resource',
             code: '403',
             status: '403' }]
        end

        it 'logs a forbidden response with AU-3 required fields' do
          allow(Rails.logger).to receive(:info)

          get :not_authorized

          expect(Rails.logger).to have_received(:info).with(
            'Forbidden access (403)',
            hash_including(
              request_id: test_request_id,
              remote_ip: test_remote_ip,
              detail: expected_detail
            )
          )
          expect(response).to have_http_status(:forbidden)
        end

        it 'does not log user_uuid' do
          allow(Rails.logger).to receive(:info)

          get :not_authorized

          expect(Rails.logger).to have_received(:info).with(
            'Forbidden access (403)',
            hash_not_including(:user_uuid)
          )
        end
      end

      context 'when a Common::Exceptions::Forbidden is raised directly' do
        it 'logs a forbidden response with AU-3 required fields' do
          allow(Rails.logger).to receive(:info)

          get :forbidden

          expect(Rails.logger).to have_received(:info).with(
            'Forbidden access (403)',
            hash_including(
              request_id: test_request_id,
              remote_ip: test_remote_ip,
              detail: [{ title: 'Forbidden', detail: 'Forbidden', code: '403', status: '403' }]
            )
          )
          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    describe '#test_authentication' do
      let(:user) { build(:user, :loa3) }
      let(:token) { 'fa0f28d6-224a-4015-a3b0-81e77de269f2' }
      let(:header_host_value) { Settings.hostname }
      let(:header_auth_value) { ActionController::HttpAuthentication::Token.encode_credentials(token) }

      before do
        session_object = Session.create(uuid: user.uuid, token:)
        User.create(user)

        session_object.to_hash.each { |k, v| session[k] = v }

        request.env['HTTP_HOST'] = header_host_value
        request.env['HTTP_AUTHORIZATION'] = header_auth_value
      end

      context 'with valid session and user' do
        it 'returns success' do
          get :test_authentication
          expect(response).to have_http_status(:ok)
        end

        it 'appends user uuid to payload' do
          get(:test_authentication)
          expect(controller.payload[:user_uuid]).to eq(user.uuid)
        end

        context 'with a credential that is locked' do
          let(:user) { build(:user, :loa3, :idme_lock) }

          it 'returns an unauthorized status' do
            get :test_authentication
            expect(response).to have_http_status(:unauthorized)
            expect(JSON.parse(response.body)['errors'].first)
              .to eq('title' => 'Not authorized', 'detail' => 'Not authorized', 'code' => '401', 'status' => '401')
          end
        end
      end

      context 'with valid session and no user' do
        before { user.destroy }

        it 'renders json error' do
          get :test_authentication
          expect(controller.instance_variable_get(:@session_object).uuid).to eq(user.uuid)
          expect(response).to have_http_status(:unauthorized)
          expect(JSON.parse(response.body)['errors'].first)
            .to eq('title' => 'Not authorized', 'detail' => 'Not authorized', 'code' => '401', 'status' => '401')
        end
      end

      context 'without valid session' do
        before { Session.find(token).destroy }

        it 'renders json error' do
          get :test_authentication
          expect(controller.instance_variable_get(:@session_object)).to be_nil
          expect(session).not_to be_empty
          expect(response).to have_http_status(:unauthorized)
          expect(JSON.parse(response.body)['errors'].first)
            .to eq('title' => 'Not authorized', 'detail' => 'Not authorized', 'code' => '401', 'status' => '401')
        end
      end
    end
  end

  describe '#sso_logging_info' do
    subject { get :test_logging }

    let(:user) { build(:user, :loa3, :legacy_icn) }
    let(:token) { 'fa0f28d6-224a-4015-a3b0-81e77de269f2' }
    let(:header_auth_value) { ActionController::HttpAuthentication::Token.encode_credentials(token) }
    let(:request_host) { Settings.hostname }
    let(:expiration_time) { Session.find(token).ttl_in_time.iso8601(0) }
    let(:sso_cookie_content) do
      {
        'patientIcn' => '123498767V234859',
        'signIn' => {
          'serviceName' => 'idme',
          'authBroker' => SignIn::Constants::Auth::BROKER_CODE,
          'clientId' => 'vaweb'
        },
        'credential_used' => 'idme',
        'credential_uuid' => user.idme_uuid,
        'user_credentials' => {
          idme: user.user_account.user_verifications.idme.count,
          logingov: user.user_account.user_verifications.logingov.count,
          clear: user.user_account.user_verifications.clear.count
        },
        'session_uuid' => token,
        'expirationTime' => expiration_time
      }
    end
    let(:expected_result) do
      {
        user_uuid: user.uuid,
        sso_cookie_contents: sso_cookie_content,
        request_host:
      }
    end

    before do
      allow(Rails.logger).to receive(:info)
      session_object = Session.create(uuid: user.uuid, token:)
      User.create(user)
      session_object.to_hash.each { |k, v| session[k] = v }
      sign_in_as(user, session_object.token)
    end

    context 'with origin logging' do
      context 'when controller has a name' do
        it 'adds controller class name as origin to logs within around_action' do
          expect(SemanticLogger).to receive(:named_tagged).with(origin: 'anonymous_controller').and_call_original
          expect(Rails.logger).to receive(:info).with(expected_result)
          subject
        end
      end

      context 'when controller class name is blank' do
        it 'does not call SemanticLogger.named_tagged when class name is blank' do
          allow(controller.class).to receive(:name).and_return('')
          expect(SemanticLogger).not_to receive(:named_tagged)
          expect(Rails.logger).to receive(:info).with(expected_result)
          subject
        end
      end
    end

    context 'when the current user and session object exist' do
      it 'returns the current user session token' do
        expect(Rails.logger).to receive(:info).with(expected_result)
        subject
      end
    end
  end
end
