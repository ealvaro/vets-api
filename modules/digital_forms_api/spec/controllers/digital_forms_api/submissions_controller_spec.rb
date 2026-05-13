# frozen_string_literal: true

require 'rails_helper'
require_relative '../../support/digital_forms_api/submission_fuzz_helpers'

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

      it 'returns a 403 error' do
        allow(Rails.logger).to receive(:warn)
        allow(monitor).to receive(:track_show)

        retrieve_submission!

        expect(response).to have_http_status(:forbidden)
        expect(Rails.logger).to have_received(:warn).with(
          'Digital Forms API - Veteran participant ID is forbidden to access this submission',
          hash_including(
            form_id: '21-686c',
            submission_id: 'abc123',
            user_participant_id_present: true
          )
        ).once
        expect(monitor).to have_received(:track_show).with(
          hash_including(
            http_status: 403,
            submission_id: 'abc123',
            form_id: '21-686c',
            failure_stage: 'authorize_submission',
            auth_denial_reason: 'participant_id_mismatch',
            duration_ms: kind_of(Integer)
          )
        ).once
      end
    end

    context "when the submission is found but current user doesn't have a Participant ID" do
      let(:cassette) { 'retrieve_686c' }
      let(:participant_id) { nil }

      it 'returns a 403 error' do
        allow(Rails.logger).to receive(:warn)
        allow(monitor).to receive(:track_show)

        retrieve_submission!

        expect(response).to have_http_status(:forbidden)
        expect(Rails.logger).to have_received(:warn).with(
          'Digital Forms API - Veteran participant ID is forbidden to access this submission',
          hash_including(
            form_id: '21-686c',
            submission_id: 'abc123',
            user_participant_id_present: false
          )
        ).once
        expect(monitor).to have_received(:track_show).with(
          hash_including(
            http_status: 403,
            submission_id: 'abc123',
            form_id: '21-686c',
            failure_stage: 'authorize_submission',
            auth_denial_reason: 'missing_participant_id',
            duration_ms: kind_of(Integer)
          )
        ).once
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

    # ------------------------------------------------------------------ #
    # Fuzz / randomized-data tests
    # Replay a failure: DF_FUZZ_SEED=<seed> bundle exec rspec <this file>
    # ------------------------------------------------------------------ #
    context 'fuzz: randomized submission payloads', :fuzz do
      include DigitalFormsApi::SubmissionFuzzHelpers

      let(:rng) { fuzz_rng }

      before do
        allow(Rails.logger).to receive(:warn)
        allow(monitor).to receive(:track_show)
        allow(monitor).to receive(:track_template_version)
      end

      after do |example|
        puts "\n[fuzz] DF_FUZZ_SEED=#{fuzz_seed}" if example.exception && ENV['DF_FUZZ_SEED'].blank?
      end

      context 'with randomized veteranId shapes' do
        it 'returns only expected status codes' do
          fuzz_iterations(rng, matching_participant_id: participant_id) do |body, veteran_id, denial|
            stub_fuzz_services(body, denial:)

            get(:show, params: { id: 'abc123' })

            expect(response.status).to(
              be_in([200, 403]),
              "[seed=#{fuzz_seed}] unexpected status #{response.status} " \
              "for veteranId=#{veteran_id.inspect}"
            )
          end
        end

        it 'never leaks veteranId value into the response' do
          fuzz_iterations(rng, matching_participant_id: participant_id) do |body, veteran_id, denial|
            stub_fuzz_services(body, denial:)

            get(:show, params: { id: 'abc123' })

            next unless veteran_id.is_a?(Hash) && veteran_id['value']

            expect(response.body.to_s).not_to(
              include(veteran_id['value']),
              "[seed=#{fuzz_seed}] PII leaked for veteranId value"
            )
          end
        end

        it 'never leaks PII in 403 responses' do
          fuzz_iterations(rng, matching_participant_id: participant_id) do |body, _veteran_id, denial|
            stub_fuzz_services(body, denial:)

            get(:show, params: { id: 'abc123' })

            next unless response.status == 403

            vet_info = body.dig('envelope', 'payload', 'veteranInformation') || {}
            pii_values = {
              'first name' => vet_info.dig('fullName', 'first'),
              'last name' => vet_info.dig('fullName', 'last'),
              'date of birth' => vet_info['dateOfBirth'],
              'SSN' => vet_info['ssn']
            }.compact

            resp_json = response.body.to_s
            pii_values.each do |label, value|
              expect(resp_json).not_to(
                include(value),
                "[seed=#{fuzz_seed}] PII leaked in 403 response: #{label}"
              )
            end
          end
        end

        it 'includes error key in all 403 responses' do
          fuzz_iterations(rng, matching_participant_id: participant_id) do |body, _veteran_id, denial|
            stub_fuzz_services(body, denial:)

            get(:show, params: { id: 'abc123' })

            next unless response.status == 403

            parsed = JSON.parse(response.body)
            expect(parsed).to(
              have_key('error'),
              "[seed=#{fuzz_seed}] 403 response missing error key"
            )
          end
        end

        it 'includes submission and template in all 200 responses' do
          fuzz_iterations(rng, matching_participant_id: participant_id) do |body, _veteran_id, denial|
            stub_fuzz_services(body, denial:)

            get(:show, params: { id: 'abc123' })

            next unless response.status == 200

            parsed = JSON.parse(response.body)
            expect(parsed).to(
              have_key('submission'),
              "[seed=#{fuzz_seed}] 200 response missing submission"
            )
            expect(parsed).to(
              have_key('template'),
              "[seed=#{fuzz_seed}] 200 response missing template"
            )
          end
        end
      end

      context 'with randomized participant_id on the user' do
        it 'returns 200 only when IDs match and 403 otherwise' do
          # Fixed valid veteranId, vary the user's participant_id
          valid_pid = '12345'
          pids = [valid_pid, nil, '', '99999', Faker::Number.number(digits: 8).to_s]

          pids.each do |pid|
            body = build(:fuzz_submission_body, rng:, matching_participant_id: valid_pid)
            stub_fuzz_services(body)

            allow_any_instance_of(User).to receive(:participant_id).and_return(pid)

            get(:show, params: { id: 'abc123' })

            if pid == valid_pid
              expect(response.status).to(
                eq(200),
                "[seed=#{fuzz_seed}] expected 200 for matching pid=#{pid}, got #{response.status}"
              )
            else
              expect(response.status).to(
                eq(403),
                "[seed=#{fuzz_seed}] expected 403 for pid=#{pid.inspect}, got #{response.status}"
              )
            end
          end
        end
      end

      context 'with every denial style explicitly' do
        %i[malformed wrong_type mismatch].each do |style|
          it "returns 403 for veteranId style=#{style}" do
            fuzz_iterations(rng, count: 5, veteran_id_style: style) do |body, veteran_id, _denial|
              stub_fuzz_services(body, denial: true)

              get(:show, params: { id: 'abc123' })

              expect(response.status).to(
                eq(403),
                "[seed=#{fuzz_seed}] expected 403 for style=#{style}, " \
                "veteranId=#{veteran_id.inspect}, " \
                "got #{response.status}"
              )
            end
          end
        end
      end

      context 'monitor tracking invariants' do
        it 'always calls track_show with required keys' do
          fuzz_iterations(rng, count: 15, matching_participant_id: participant_id) do |body, _veteran_id, denial|
            stub_fuzz_services(body, denial:)

            expect(monitor).to receive(:track_show).with(
              hash_including(
                http_status: kind_of(Integer),
                submission_id: 'abc123',
                form_id: '21-686c'
              )
            )

            get(:show, params: { id: 'abc123' })
          end
        end
      end
    end
  end
end
