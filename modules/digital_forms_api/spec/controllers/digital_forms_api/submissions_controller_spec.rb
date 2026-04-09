# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DigitalFormsApi::SubmissionsController, type: :controller do
  routes { DigitalFormsApi::Engine.routes }

  let(:participant_id) { '12345' }
  let(:user) { create(:evss_user, participant_id:) }
  let(:flipper_enabled) { true }
  let(:monitor) do
    instance_double(DigitalFormsApi::Monitor::Controller, track_show: true, track_template_version: true)
  end

  before do
    sign_in_as(user) if user.present?
    allow(Flipper).to receive(:enabled?).with(:dependents_digital_forms_api_submission_enabled,
                                              instance_of(User)).and_return(flipper_enabled)
    allow_any_instance_of(described_class).to receive(:monitor).and_return(monitor)
  end

  describe '#show' do
    def retrieve_submission!
      VCR.use_cassette("digital_forms/#{cassette}") do
        get(:show, params: { id: 'abc123' })
      end
    end

    context 'when the submission is found and matches the current user' do
      let(:cassette) { 'retrieve_686c' }

      it 'returns the submission and template' do
        expect(monitor).to receive(:track_template_version).with(form_id: '21-686c', template_version: '1.0')
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 200,
                                                       submission_id: 'abc123',
                                                       form_id: '21-686c',
                                                       template_version: '1.0',
                                                       failure_stage: 'none',
                                                       duration_ms: kind_of(Integer)
                                                     ))
        VCR.use_cassette('digital_forms/template_686c') do
          retrieve_submission!
        end
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body).to include(
          { 'submission' => include(
            { 'veteranInformation' => include(
              { 'fullName' =>
                { 'first' => 'John', 'last' => 'Doe' } }
            ) }
          ),
            'template' => include(
              { 'formId' => '21-686c',
                'version' => '1.0' }
            ) }
        )
      end
    end

    context "when the submission is found but doesn't match the current user" do
      let(:cassette) { 'retrieve_686c' }
      let(:participant_id) { '54321' }

      it 'returns a 403 error', skip: 'Flaky test, needs investigation' do
        expect(Rails.logger).to receive(:warn).with(
          'Digital Form API - Veteran participant ID is forbidden to access this submission',
          hash_including(
            form_id: '21-686c',
            submission_id: 'abc123',
            user_participant_id_present: true
          )
        )
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 403,
                                                       submission_id: 'abc123',
                                                       form_id: '21-686c',
                                                       failure_stage: 'authorize_submission',
                                                       auth_denial_reason: 'participant_id_mismatch',
                                                       duration_ms: kind_of(Integer)
                                                     ))
        retrieve_submission!
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when the submission is found but current user doesn't have a Participant ID" do
      let(:cassette) { 'retrieve_686c' }
      let(:participant_id) { nil }

      it 'returns a 403 error', skip: 'Flaky test, needs investigation' do
        expect(Rails.logger).to receive(:warn).with(
          'Digital Form API - Veteran participant ID is forbidden to access this submission',
          hash_including(
            form_id: '21-686c',
            submission_id: 'abc123',
            user_participant_id_present: false
          )
        )
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 403,
                                                       submission_id: 'abc123',
                                                       form_id: '21-686c',
                                                       failure_stage: 'authorize_submission',
                                                       auth_denial_reason: 'missing_participant_id',
                                                       duration_ms: kind_of(Integer)
                                                     ))
        retrieve_submission!
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the submission veteranId is not a Hash' do
      let(:cassette) { 'retrieve_686c' }

      before do
        allow_any_instance_of(DigitalFormsApi::Service::Submissions).to receive(:retrieve).and_return(
          OpenStruct.new(body: { 'envelope' => { 'veteranId' => 'not-a-hash', 'payload' => {} } })
        )
      end

      it 'returns a 403 with malformed_veteran_id denial reason' do
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 403,
                                                       failure_stage: 'authorize_submission',
                                                       auth_denial_reason: 'malformed_veteran_id'
                                                     ))
        retrieve_submission!
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the submission veteranId has a non-PARTICIPANTID identifier type' do
      let(:cassette) { 'retrieve_686c' }

      before do
        allow_any_instance_of(DigitalFormsApi::Service::Submissions).to receive(:retrieve).and_return(
          OpenStruct.new(body: { 'envelope' => {
                           'veteranId' => { 'identifierType' => 'SSN', 'value' => '12345' },
                           'payload' => {}
                         } })
        )
      end

      it 'returns a 403 with identifier_type_mismatch denial reason' do
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 403,
                                                       failure_stage: 'authorize_submission',
                                                       auth_denial_reason: 'identifier_type_mismatch'
                                                     ))
        retrieve_submission!
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the submission is not found' do
      let(:cassette) { 'retrieve_686c_404' }

      it 'returns a 404 error' do
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 404,
                                                       submission_id: 'abc123',
                                                       form_id: '21-686c',
                                                       failure_stage: 'retrieve_submission',
                                                       error_source: 'client_error',
                                                       duration_ms: kind_of(Integer),
                                                       upstream_status: 404,
                                                       upstream_reason: kind_of(String),
                                                       error_class: kind_of(String),
                                                       error: kind_of(String)
                                                     ))
        retrieve_submission!
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when Forms API returns a non-404 client error' do
      let(:cassette) { 'retrieve_686c_403' }

      it 'returns a 500 error' do
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 500,
                                                       submission_id: 'abc123',
                                                       form_id: '21-686c',
                                                       failure_stage: 'retrieve_submission',
                                                       error_source: 'client_error',
                                                       duration_ms: kind_of(Integer),
                                                       upstream_status: 403,
                                                       upstream_reason: kind_of(String),
                                                       error_class: kind_of(String),
                                                       error: kind_of(String)
                                                     ))
        retrieve_submission!
        expect(response).to have_http_status(:internal_server_error)
      end
    end

    context 'when user is not logged in' do
      let(:user) { nil }

      it 'returns a 401 error without hitting Forms API' do
        get(:show, params: { id: 'abc123' })
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the Flipper flag is off' do
      let(:flipper_enabled) { false }

      it 'returns a 403 error without hitting Forms API' do
        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 403,
                                                       submission_id: 'abc123',
                                                       form_id: '21-686c',
                                                       failure_stage: 'feature_flag',
                                                       auth_denial_reason: 'feature_flag_disabled',
                                                       feature_flag_enabled: false
                                                     ))
        get(:show, params: { id: 'abc123' })
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when a non-FormsAPI error occurs' do
      let(:cassette) { 'retrieve_686c' }

      it 'tracks and returns a 500 without upstream context' do
        allow_any_instance_of(DigitalFormsApi::Service::Templates).to receive(:template)
          .and_raise(RuntimeError, 'Template failure')

        expect(monitor).to receive(:track_show).with(hash_including(
                                                       http_status: 500,
                                                       submission_id: 'abc123',
                                                       form_id: '21-686c',
                                                       failure_stage: 'fetch_template',
                                                       error_source: 'unexpected_error',
                                                       duration_ms: kind_of(Integer),
                                                       error_class: 'RuntimeError',
                                                       error: 'Template failure'
                                                     ))

        retrieve_submission!
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end
end
