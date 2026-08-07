# frozen_string_literal: true

require 'rails_helper'
require 'support/controller_spec_helper'
require 'disability_compensation/factories/api_provider_factory'

# Because of the shared_example this is behaving like a controller and request spec
RSpec.describe V0::DisabilityCompensationInProgressFormsController do
  it_behaves_like 'a controller that does not log 404'

  context 'with a user' do
    let(:loa3_user) { build(:disabilities_compensation_user) }
    let(:loa1_user) { build(:user, :loa1) }

    describe '#show' do
      before do
        allow(Flipper).to receive(:enabled?).with(:disability_compensation_sync_modern_0781_flow, instance_of(User))
        allow(Flipper).to receive(:enabled?).with(:intent_to_file_lighthouse_enabled, instance_of(User))
      end

      context 'using the Lighthouse Rated Disabilities Provider' do
        let(:rated_disabilities_from_lighthouse) do
          [{ 'name' => 'Diabetes mellitus0',
             'ratedDisabilityId' => '1',
             'ratingDecisionId' => '0',
             'diagnosticCode' => 5238,
             'decisionCode' => 'SVCCONNCTED',
             'decisionText' => 'Service Connected',
             'ratingPercentage' => 50,
             'maximumRatingPercentage' => nil }]
        end

        let(:lighthouse_user) { build(:evss_user, icn: '123498767V234859') }

        let!(:in_progress_form_lighthouse) do
          form_json = JSON.parse(
            File.read(
              'spec/support/disability_compensation_form/' \
              '526_in_progress_form_minimal_lighthouse_rated_disabilities.json'
            )
          )
          create(:in_progress_form,
                 user_uuid: lighthouse_user.uuid,
                 form_id: '21-526EZ',
                 form_data: form_json['formData'],
                 metadata: form_json['metadata'])
        end

        # Helper that modifies form_data, triggers disability_rating/200_response, and returns the json response
        def get_response_for_disability_rating(form_data_mod: nil)
          fd = JSON.parse(in_progress_form_lighthouse.form_data)
          form_data_mod&.call(fd)
          in_progress_form_lighthouse.update(form_data: fd)

          VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
            VCR.use_cassette('disability_max_ratings/max_ratings') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end
          end

          expect(response).to have_http_status(:ok)
          JSON.parse(response.body)
        end

        before do
          allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('blahblech')

          sign_in_as(lighthouse_user)
        end

        context 'IPF ID logging on show' do
          it 'logs the in_progress_form_id and return_url when an existing form is found' do
            raw_meta = in_progress_form_lighthouse[:metadata] || {}
            raw_meta['returnUrl'] = '/veteran-information'
            in_progress_form_lighthouse.update!(metadata: raw_meta)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 InProgressForm show',
              hash_including(
                in_progress_form_id: in_progress_form_lighthouse.id,
                user_uuid: lighthouse_user.uuid,
                return_url: '/veteran-information'
              )
            )

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
          end

          it 'logs return_url from snake_case metadata key' do
            raw_meta = in_progress_form_lighthouse[:metadata] || {}
            raw_meta.delete('returnUrl')
            raw_meta['return_url'] = '/contact-information'
            in_progress_form_lighthouse.update!(metadata: raw_meta)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 InProgressForm show',
              hash_including(
                in_progress_form_id: in_progress_form_lighthouse.id,
                return_url: '/contact-information'
              )
            )

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
          end

          it 'logs user_uuid for prefill when no existing form is found' do
            sign_in_as(loa1_user)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 InProgressForm show (prefill IPF)',
              hash_including(
                user_uuid: loa1_user.uuid
              )
            )

            get v0_disability_compensation_in_progress_form_url('21-526EZ'), params: nil

            expect(response).to have_http_status(:ok)
          end

          it 'does not log PII in any attributes' do
            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with('Form526 InProgressForm show', anything) do |_message, attrs|
              expect(attrs).not_to have_key(:form_data)
              expect(attrs).not_to have_key(:ssn)
              expect(attrs).not_to have_key(:name)
            end

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end
          end
        end

        context 'IPF activity prefill engagement event' do
          it 'emits a prefill engagement event when no IPF exists yet' do
            sign_in_as(loa1_user)
            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'prefill',
                in_progress_form_id: nil,
                user_uuid: loa1_user.uuid,
                form_id: FormProfiles::VA526ez::FORM_ID,
                terminal: false
              )
            )

            get v0_disability_compensation_in_progress_form_url('21-526EZ'), params: nil

            expect(response).to have_http_status(:ok)
          end
        end

        context 'IPF activity heartbeat event edge cases and error handling' do
          let(:update_user) { loa3_user }
          let(:new_form) { build(:in_progress_form, form_id: FormProfiles::VA526ez::FORM_ID) }

          before do
            sign_in_as(update_user)
          end

          it 'logs update heartbeat with correct request_id and controller info' do
            # Create form first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'update',
                controller: 'V0::DisabilityCompensationInProgressFormsController',
                action: 'update',
                request_id: kind_of(String)
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end

          it 'logs prefill event with nil in_progress_form_id' do
            sign_in_as(loa1_user)
            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'prefill',
                in_progress_form_id: nil,
                terminal: false
              )
            )

            get v0_disability_compensation_in_progress_form_url('21-526EZ'), params: nil

            expect(response).to have_http_status(:ok)
          end

          it 'handles active_delta_seconds correctly for very recent updates' do
            # Create the IPF first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            existing_form = InProgressForm.form_for_user(new_form.form_id, update_user)
            # Set updated_at to very recent (30 seconds ago)
            metadata = (existing_form[:metadata] || {}).deep_dup
            metadata['lastSessionActivityAt'] = 30.seconds.ago.utc.iso8601(3)
            existing_form.update!(metadata:)

            allow(Rails.logger).to receive(:info).and_call_original
            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'update',
                active_delta_seconds: a_value_within(5).of(30)
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end

          it 'reports the full active_delta_seconds and flags idle gap exceeded' do
            # Create the IPF first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            existing_form = InProgressForm.form_for_user(new_form.form_id, update_user)
            # Set lastSessionActivityAt to beyond idle gap (15 minutes > 10-minute gap)
            metadata = (existing_form[:metadata] || {}).deep_dup
            metadata['lastSessionActivityAt'] = 15.minutes.ago.utc.iso8601(3)
            existing_form.update!(metadata:)

            allow(Rails.logger).to receive(:info).and_call_original
            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'update',
                active_delta_seconds: a_value_within(5).of(15.minutes.to_i),
                active_idle_gap_exceeded: true
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end

          it 'includes form_id in all engagement events' do
            # Create form first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(form_id: FormProfiles::VA526ez::FORM_ID)
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
          end

          it 'includes user_uuid in all engagement events' do
            # Create form first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(user_uuid: update_user.uuid)
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
          end

          it 'includes occurred_at timestamp in ISO8601 format for all events' do
            # Create form first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                occurred_at: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
          end

          it 'logs interaction event with event_type: update' do
            # Create form first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(event_type: 'update')
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
          end
        end

        context 'when a form is found and rated_disabilities have updates' do
          it 'returns the form as JSON' do
            # change form data
            json_response = get_response_for_disability_rating(
              form_data_mod: lambda do |fd|
                fd['ratedDisabilities'].first['diagnosticCode'] = '111'
              end
            )
            expect(json_response['formData']['ratedDisabilities'])
              .to eq(
                JSON.parse(in_progress_form_lighthouse.form_data)['ratedDisabilities']
              )
            expect(json_response['formData']['updatedRatedDisabilities']).to eq(rated_disabilities_from_lighthouse)
            expect(json_response['metadata']['returnUrl']).to eq('/disabilities/rated-disabilities')
          end

          it "sets returnUrl to 'conditions/summary' when new-flow is true (boolean)" do
            json_response = get_response_for_disability_rating(
              form_data_mod: lambda do |fd|
                fd['ratedDisabilities'].first['diagnosticCode'] = '111'
                fd['disability_comp_new_conditions_workflow'] = true
              end
            )
            expect(json_response['metadata']['returnUrl']).to eq('/conditions/summary')
          end

          it "sets returnUrl to 'conditions/summary' when new-flow is 'true' (string)" do
            json_response = get_response_for_disability_rating(
              form_data_mod: lambda do |fd|
                fd['ratedDisabilities'].first['diagnosticCode'] = '111'
                fd['disability_comp_new_conditions_workflow'] = 'true'
              end
            )
            expect(json_response['metadata']['returnUrl']).to eq('/conditions/summary')
          end

          it "sets returnUrl to '/disabilities/rated-disabilities' when new-flow is false" do
            json_response = get_response_for_disability_rating(
              form_data_mod: lambda do |fd|
                fd['ratedDisabilities'].first['diagnosticCode'] = '111'
                fd['disability_comp_new_conditions_workflow'] = false
              end
            )
            expect(json_response['metadata']['returnUrl']).to eq('/disabilities/rated-disabilities')
          end

          it "sets returnUrl to '/disabilities/rated-disabilities' when new-flow key is not present" do
            json_response = get_response_for_disability_rating(
              form_data_mod: lambda do |fd|
                fd['ratedDisabilities'].first['diagnosticCode'] = '111'
                fd.delete('disability_comp_new_conditions_workflow')
              end
            )
            expect(json_response['metadata']['returnUrl']).to eq('/disabilities/rated-disabilities')
          end

          it 'returns an unaltered form if Lighthouse returns an error' do
            rated_disabilities_before = JSON.parse(in_progress_form_lighthouse.form_data)['ratedDisabilities']
            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/503_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['ratedDisabilities']).to eq(rated_disabilities_before)
            expect(json_response['formData']['updatedRatedDisabilities']).to be_nil
            expect(json_response['metadata']['returnUrl']).to eq('/va-employee')
          end
        end

        context 'when a form is found and rated_disabilities are unchanged' do
          it 'returns the form as JSON' do
            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['ratedDisabilities'])
              .to eq(
                JSON.parse(in_progress_form_lighthouse.form_data)['ratedDisabilities']
              )

            expect(json_response['formData']['updatedRatedDisabilities']).to be_nil
            expect(json_response['metadata']['returnUrl']).to eq('/va-employee')
          end
        end

        context 'when toxic exposure' do
          it 'returns startedFormVersion as 2019 for existing InProgressForms' do
            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['startedFormVersion']).to eq('2019')
          end
        end

        context 'prefills formData when user does not have an InProgressForm pending submission' do
          let(:user) { loa1_user }
          let!(:form_id) { '21-526EZ' }

          before do
            sign_in_as(user)
          end

          it 'adds default startedFormVersion for new InProgressForm' do
            get v0_disability_compensation_in_progress_form_url(form_id), params: nil
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['startedFormVersion']).to eq('2022')
          end

          it 'returns 2022 when existing IPF with 2022 as startedFormVersion' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data['startedFormVersion'] = '2022'
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!
            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']['startedFormVersion']).to eq('2022')
            end
          end
        end

        context 'log_started_form_version logging' do
          it 'returns form data when startedFormVersion is present' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data['startedFormVersion'] = '2022'
            parsed_form_data.delete('started_form_version')
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            # With && logic, having just startedFormVersion is sufficient to preserve the value
            expect(json_response['formData']['startedFormVersion']).to eq('2022')
          end

          it 'sets default to 2019 when both startedFormVersion keys are missing from existing IPF' do
            # Remove both version keys to trigger the set_started_form_version path
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data.delete('startedFormVersion')
            parsed_form_data.delete('started_form_version')
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            # Request should still succeed and return the form with default 2019 version
            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['startedFormVersion']).to eq('2019')
          end

          it 'does not break the response when logging succeeds' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data['startedFormVersion'] = '2019'
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response).to have_key('formData')
            expect(json_response).to have_key('metadata')
            expect(json_response['formData']['startedFormVersion']).to eq('2019')
          end

          it 'returns startedFormVersion 2022 for prefilled new InProgressForm' do
            sign_in_as(loa1_user)

            get v0_disability_compensation_in_progress_form_url('21-526EZ'), params: nil

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['startedFormVersion']).to eq('2022')
          end

          it 'preserves existing startedFormVersion value' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data['startedFormVersion'] = '2019'
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['startedFormVersion']).to eq('2019')
          end

          it 'preserves startedFormVersion when only started_form_version is present' do
            # Only set snake_case version
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data.delete('startedFormVersion')
            parsed_form_data['started_form_version'] = '2022'
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            # With && logic, having just started_form_version prevents default override
            expect(json_response['formData']['started_form_version']).to eq('2022')
          end
        end

        context 'set_started_form_version logic (&& not ||)' do
          it 'does NOT override when only camelCase startedFormVersion is present' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data['startedFormVersion'] = '2022'
            parsed_form_data.delete('started_form_version')
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            # Should preserve 2022 because && requires BOTH to be blank
            expect(json_response['formData']['startedFormVersion']).to eq('2022')
          end

          it 'does NOT override when only snake_case started_form_version is present' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data.delete('startedFormVersion')
            parsed_form_data['started_form_version'] = '2022'
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            # Should NOT add startedFormVersion = 2019 because started_form_version exists
            expect(json_response['formData']['startedFormVersion']).to be_nil
            expect(json_response['formData']['started_form_version']).to eq('2022')
          end

          it 'sets default 2019 ONLY when both keys are missing' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data.delete('startedFormVersion')
            parsed_form_data.delete('started_form_version')
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            # Should set default because BOTH are missing
            expect(json_response['formData']['startedFormVersion']).to eq('2019')
          end

          it 'preserves value when both keys are present' do
            parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
            parsed_form_data['startedFormVersion'] = '2022'
            parsed_form_data['started_form_version'] = '2022'
            in_progress_form_lighthouse.form_data = parsed_form_data.to_json
            in_progress_form_lighthouse.save!

            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
            end

            expect(response).to have_http_status(:ok)
            json_response = JSON.parse(response.body)
            expect(json_response['formData']['startedFormVersion']).to eq('2022')
          end
        end

        context 'fix_duplicate_key_ipf (additional information cleanup)' do
          let(:duplicate_key_fix_toggle) { :disability_compensation_fix_duplicate_key_ipf }

          context 'when fix_duplicate_key_ipf toggle is ON' do
            before do
              allow(Flipper).to receive(:enabled?).with(duplicate_key_fix_toggle, instance_of(User)).and_return(true)
            end

            it 'removes camelCase additionalInformation when value is an empty object' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additionalInformation'] = {}
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']).not_to have_key('additionalInformation')
            end

            it 'removes snake_case additional_information when value is an empty object' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additional_information'] = {}
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']).not_to have_key('additional_information')
            end

            it 'removes camelCase additionalInformation when value is an empty array' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additionalInformation'] = []
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']).not_to have_key('additionalInformation')
            end

            it 'removes snake_case additional_information when value is an empty array' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additional_information'] = []
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']).not_to have_key('additional_information')
            end

            it 'preserves additionalInformation when it contains text' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additionalInformation'] = 'Additional information text.'
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']['additionalInformation']).to eq('Additional information text.')
            end

            it 'preserves additional_information when it contains text' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additional_information'] = 'Additional information text.'
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']['additional_information']).to eq('Additional information text.')
            end
          end

          context 'when fix_duplicate_key_ipf toggle is OFF' do
            before do
              allow(Flipper).to receive(:enabled?).with(duplicate_key_fix_toggle, instance_of(User)).and_return(false)
            end

            it 'does not remove empty camelCase additionalInformation' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additionalInformation'] = {}
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']['additionalInformation']).to eq({})
            end

            it 'does not remove empty snake_case additional_information' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['additional_information'] = {}
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']['additional_information']).to eq({})
            end
          end
        end

        context 'fix_new_conditions_workflow_flag (returnUrl-based)' do
          let(:fix_toggle) { :disability_compensation_fix_poisoned_ipf }

          context 'DB round-trip key casing verification' do
            before do
              allow(Flipper).to receive(:enabled?).with(fix_toggle, instance_of(User)).and_return(true)
            end

            it 'stores and retrieves the workflow flag as snake_case (disability_comp_new_conditions_workflow)' do
              # Write snake_case key into form_data — this matches how OliveBranch stores it in production
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['disability_comp_new_conditions_workflow'] = true
              raw_meta = in_progress_form_lighthouse[:metadata] || {}
              raw_meta['returnUrl'] = '/new-disabilities/follow-up/0'
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

              # Verify the key is persisted as snake_case in the DB
              in_progress_form_lighthouse.reload
              db_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              expect(db_form_data).to have_key('disability_comp_new_conditions_workflow')
              expect(db_form_data).not_to have_key('disabilityCompNewConditionsWorkflow')
              expect(db_form_data['disability_comp_new_conditions_workflow']).to be(true)

              # Now hit the endpoint — the fix should see the snake_case key and reset it
              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)

              # Verify the fix persisted to the DB as snake_case
              in_progress_form_lighthouse.reload
              persisted = JSON.parse(in_progress_form_lighthouse.form_data)
              expect(persisted).to have_key('disability_comp_new_conditions_workflow')
              expect(persisted).not_to have_key('disabilityCompNewConditionsWorkflow')
              expect(persisted['disability_comp_new_conditions_workflow']).to be(false)
            end
          end

          context 'when fix_poisoned_ipf toggle is OFF (kill switch)' do
            before do
              allow(Flipper).to receive(:enabled?).with(fix_toggle, instance_of(User)).and_return(false)
            end

            it 'does not modify the flag even when returnUrl is an old-flow page' do
              parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
              parsed_form_data['disability_comp_new_conditions_workflow'] = true
              raw_meta = in_progress_form_lighthouse[:metadata] || {}
              raw_meta['returnUrl'] = '/new-disabilities/follow-up/0'
              in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(true)
            end
          end

          context 'when fix_poisoned_ipf toggle is ON' do
            before do
              allow(Flipper).to receive(:enabled?).with(fix_toggle, instance_of(User)).and_return(true)
            end

            context 'when flag is true and returnUrl is an old-flow conditions page' do
              it 'resets flag to false' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/new-disabilities/follow-up/0'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'resets for follow-up intro page too' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/new-disabilities/follow-up'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'persists the fix to the database' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/new-disabilities/follow-up/0'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                in_progress_form_lighthouse.reload
                persisted = JSON.parse(in_progress_form_lighthouse.form_data)
                expect(persisted['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'handles string "true" the same as boolean true' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = 'true'
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/new-disabilities/follow-up/0'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'resets for new-disabilities/add page (redirect loop)' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/new-disabilities/add'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'resets for claim-type page (redirect loop)' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/claim-type'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'resets for disabilities/orientation page (redirect loop)' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/disabilities/orientation'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'resets for disabilities/rated-disabilities page (redirect loop)' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/disabilities/rated-disabilities'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end
            end

            context 'when flag is true but returnUrl is NOT an old-flow conditions page' do
              it 'keeps flag true when returnUrl is a safe page' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/veteran-information'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(true)
              end

              it 'keeps flag true when returnUrl is a new-flow conditions page' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/conditions/summary'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(true)
              end

              it 'keeps flag true when returnUrl is new-disabilities/additional-remarks-781 (not add)' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = true
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/new-disabilities/additional-remarks-781'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(true)
              end
            end

            context 'when flag is not true' do
              it 'does nothing when flag is false' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data['disability_comp_new_conditions_workflow'] = false
                raw_meta = in_progress_form_lighthouse[:metadata] || {}
                raw_meta['returnUrl'] = '/new-disabilities/follow-up/0'
                in_progress_form_lighthouse.update!(form_data: parsed_form_data.to_json, metadata: raw_meta)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be(false)
              end

              it 'does nothing when flag is absent' do
                parsed_form_data = JSON.parse(in_progress_form_lighthouse.form_data)
                parsed_form_data.delete('disability_comp_new_conditions_workflow')
                in_progress_form_lighthouse.update(form_data: parsed_form_data.to_json)

                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['disability_comp_new_conditions_workflow']).to be_nil
              end
            end
          end
        end

        context 'as_json optimization for updatedRatedDisabilities' do
          it 'returns correctly formatted updatedRatedDisabilities when disabilities change' do
            # Change form data to trigger the update path
            # Verify the structure is correct (as_json produces same output as JSON.parse(to_json))
            json_response = get_response_for_disability_rating(
              form_data_mod: lambda do |fd|
                fd['ratedDisabilities'].first['diagnosticCode'] = '111'
              end
            )
            updated_disabilities = json_response['formData']['updatedRatedDisabilities']
            expect(updated_disabilities).to be_an(Array)
            expect(updated_disabilities).not_to be_empty
            expect(updated_disabilities.first).to have_key('name')
            expect(updated_disabilities.first).to have_key('ratedDisabilityId')
            expect(updated_disabilities.first).to have_key('diagnosticCode')
          end

          it 'returns nil updatedRatedDisabilities when disabilities have not changed' do
            # Don't modify form data - disabilities should match
            json_response = get_response_for_disability_rating(
              form_data_mod: nil
            )
            expect(json_response['formData']['updatedRatedDisabilities']).to be_nil
          end

          it 'sets returnUrl when rated disabilities have updates and claimingIncrease is true' do
            json_response = get_response_for_disability_rating(
              form_data_mod: lambda do |fd|
                fd['ratedDisabilities'].first['diagnosticCode'] = '111'
                fd['view:claimType'] = { 'view:claimingIncrease' => true }
              end
            )
            expect(json_response['metadata']['returnUrl']).to eq('/disabilities/rated-disabilities')
          end
        end

        context 'rated_disabilities_from_api_provider logging' do
          context 'when initialize_rated_disabilities_information raises an error' do
            let(:error) { Common::Exceptions::Timeout.new }

            before do
              allow_any_instance_of(FormProfiles::VA526ez)
                .to receive(:initialize_rated_disabilities_information)
                .and_raise(error)
            end

            it 'logs a warning with the error class and message' do
              expect(Rails.logger).to receive(:warn).with(
                'Form526 IPF failed to fetch rated disabilities',
                { error: error.class, message: error.message }
              )

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end
            end

            it 'still returns a successful response' do
              allow(Rails.logger).to receive(:warn)

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
              end

              expect(response).to have_http_status(:ok)
            end
          end

          context 'when initialize_rated_disabilities_information succeeds' do
            it 'does not log a warning' do
              expect(Rails.logger).not_to receive(:warn).with(
                'Form526 IPF failed to fetch rated disabilities',
                anything
              )

              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                VCR.use_cassette('disability_max_ratings/max_ratings') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil
                end
              end
            end
          end
        end

        context 'ratedDisabilitiesFetchFailed flag' do
          context 'when the IPF has ratedDisabilitiesFetchFailed: true (fetch failed during prefill)' do
            before do
              fd = JSON.parse(in_progress_form_lighthouse.form_data)
              fd['ratedDisabilitiesFetchFailed'] = true
              in_progress_form_lighthouse.update!(form_data: fd.to_json)
            end

            context 'and the retry fetch succeeds' do
              it 'clears ratedDisabilitiesFetchFailed from the response' do
                VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                  VCR.use_cassette('disability_max_ratings/max_ratings') do
                    get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id),
                        params: nil
                  end
                end

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']).not_to have_key('ratedDisabilitiesFetchFailed')
              end
            end

            context 'and the retry fetch also fails (raises an exception)' do
              before do
                allow_any_instance_of(FormProfiles::VA526ez)
                  .to receive(:initialize_rated_disabilities_information)
                  .and_raise(Common::Exceptions::Timeout.new)
                allow(Rails.logger).to receive(:warn)
              end

              it 'preserves ratedDisabilitiesFetchFailed in the response' do
                get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil

                expect(response).to have_http_status(:ok)
                json_response = JSON.parse(response.body)
                expect(json_response['formData']['ratedDisabilitiesFetchFailed']).to be(true)
              end
            end
          end

          context 'when the IPF does not have ratedDisabilitiesFetchFailed set' do
            it 'does not add ratedDisabilitiesFetchFailed to the response when the fetch succeeds' do
              VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
                VCR.use_cassette('disability_max_ratings/max_ratings') do
                  get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id),
                      params: nil
                end
              end

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']).not_to have_key('ratedDisabilitiesFetchFailed')
            end

            it 'does not add ratedDisabilitiesFetchFailed to the response when the fetch fails' do
              allow_any_instance_of(FormProfiles::VA526ez)
                .to receive(:initialize_rated_disabilities_information)
                .and_raise(Common::Exceptions::Timeout.new)
              allow(Rails.logger).to receive(:warn)

              get v0_disability_compensation_in_progress_form_url(in_progress_form_lighthouse.form_id), params: nil

              expect(response).to have_http_status(:ok)
              json_response = JSON.parse(response.body)
              expect(json_response['formData']).not_to have_key('ratedDisabilitiesFetchFailed')
            end
          end
        end
      end

      describe '#update' do
        let(:update_user) { loa3_user }
        let(:new_form) { build(:in_progress_form, form_id: FormProfiles::VA526ez::FORM_ID) }
        let(:flipper0781) { :disability_compensation_sync_modern0781_flow_metadata }
        let(:flipper_new_conditions) { :disability_compensation_new_conditions_workflow_metadata }

        before do
          sign_in_as(update_user)
        end

        it 'inserts the form', run_at: '2017-01-01' do
          expect do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
          end.to change(InProgressForm, :count).by(1)
          expect(response).to have_http_status(:ok)
        end

        it 'adds 0781 metadata if flipper enabled' do
          allow(Flipper).to receive(:enabled?).with(flipper0781).and_return(true)
          put v0_disability_compensation_in_progress_form_url(new_form.form_id),
              params: {
                form_data: { greeting: 'Hello!' },
                metadata: new_form.metadata
              }.to_json,
              headers: { 'CONTENT_TYPE' => 'application/json' }
          # Checking key present, it will be false regardless due to prefill not running
          expect(JSON.parse(response.body)['data']['attributes']['metadata'].key?('sync_modern0781_flow')).to be(true)
          expect(response).to have_http_status(:ok)
        end

        it 'does not add 0781 metadata if form and flipper disabled' do
          allow(Flipper).to receive(:enabled?).with(flipper0781).and_return(false)
          put v0_disability_compensation_in_progress_form_url(new_form.form_id),
              params: {
                form_data: { greeting: 'Hello!' },
                metadata: new_form.metadata
              }.to_json,
              headers: { 'CONTENT_TYPE' => 'application/json' }
          expect(JSON.parse(response.body)['data']['attributes']['metadata'].key?('sync_modern0781_flow')).to be(false)
          expect(response).to have_http_status(:ok)
        end

        context 'IPF ID logging on update' do
          it 'logs the in_progress_form_id after a successful update' do
            # Create the form first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: { returnUrl: '/veteran-information' }
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)

            created_form = InProgressForm.form_for_user(new_form.form_id, update_user)

            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 InProgressForm update',
              hash_including(
                in_progress_form_id: created_form.id,
                user_uuid: update_user.uuid,
                return_url: '/veteran-information'
              )
            )

            # Update it
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: { returnUrl: '/veteran-information' }
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end

          it 'logs the return_url from metadata params' do
            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 InProgressForm update',
              hash_including(
                return_url: '/supporting-evidence/evidence-types'
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: { returnUrl: '/supporting-evidence/evidence-types' }
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end
        end

        context 'IPF activity heartbeat event on update' do
          it 'emits a heartbeat log event after a successful update' do
            allow(Rails.logger).to receive(:info).and_call_original

            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'update',
                in_progress_form_id: be_a(Integer),
                user_uuid: update_user.uuid,
                form_id: FormProfiles::VA526ez::FORM_ID,
                terminal: false
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end

          it 'emits active_delta_seconds for update when previous activity is recent' do
            # create the IPF first
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            existing_form = InProgressForm.form_for_user(new_form.form_id, update_user)
            metadata = (existing_form[:metadata] || {}).deep_dup
            metadata['lastSessionActivityAt'] = 2.minutes.ago.utc.iso8601(3)
            existing_form.update!(metadata:)

            allow(Rails.logger).to receive(:info).and_call_original
            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'update',
                in_progress_form_id: existing_form.id,
                active_delta_seconds: a_value_within(5).of(2.minutes.to_i)
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end

          it 'resets lastSessionActivityAt on session boundary (show resets for next update)' do
            # Create the IPF at midnight
            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
            expect(response).to have_http_status(:ok)

            existing_form = InProgressForm.form_for_user(new_form.form_id, update_user)

            # Simulate prior session activity older than the current session start.
            metadata = (existing_form[:metadata] || {}).deep_dup
            previous_session_activity_at = 2.minutes.ago
            metadata['lastSessionActivityAt'] = previous_session_activity_at.utc.iso8601(3)
            existing_form.update!(metadata:)

            # Simulate session break: user logs off and returns 8 hours later (show action)
            # Show should reset lastSessionActivityAt to mark new session start
            VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
              get v0_disability_compensation_in_progress_form_url(new_form.form_id), params: nil
            end
            expect(response).to have_http_status(:ok)

            # Verify show reset the lastSessionActivityAt to current time
            reloaded_form = InProgressForm.form_for_user(new_form.form_id, update_user)
            current_last_session_activity_at = Time.zone.parse(reloaded_form[:metadata]['lastSessionActivityAt'])
            expect(current_last_session_activity_at).to be > previous_session_activity_at

            # Now user updates in the new session.
            allow(Rails.logger).to receive(:info).and_call_original
            expect(Rails.logger).to receive(:info).with(
              'Form526 interaction',
              hash_including(
                event_type: 'update',
                in_progress_form_id: reloaded_form.id,
                # Delta should be near zero right after session reset on show.
                active_delta_seconds: a_value_within(5).of(0)
              )
            )

            put v0_disability_compensation_in_progress_form_url(new_form.form_id), params: {
              formData: new_form.form_data,
              metadata: new_form.metadata
            }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

            expect(response).to have_http_status(:ok)
          end
        end

        context 'when flipper is enabled for 0781 metadata sync' do
          before do
            allow(Flipper).to receive(:enabled?).with(flipper0781).and_return(true)
          end

          it 'sets sync_modern0781_flow to true when form_data contains sync_modern0781_flow: true' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!', sync_modern0781_flow: true },
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['sync_modern0781_flow']).to be(true)
            expect(response).to have_http_status(:ok)
          end

          it 'sets sync_modern0781_flow to false when form_data contains sync_modern0781_flow: false' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!', sync_modern0781_flow: false },
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['sync_modern0781_flow']).to be(false)
            expect(response).to have_http_status(:ok)
          end

          it 'defaults sync_modern0781_flow to false when not present in form_data' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!' },
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['sync_modern0781_flow']).to be(false)
            expect(response).to have_http_status(:ok)
          end

          it 'handles form_data as a JSON string' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!', sync_modern0781_flow: true }.to_json,
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['sync_modern0781_flow']).to be(true)
            expect(response).to have_http_status(:ok)
          end
        end

        it 'adds new conditions workflow metadata if flipper enabled' do
          allow(Flipper).to receive(:enabled?).with(flipper_new_conditions).and_return(true)
          put v0_disability_compensation_in_progress_form_url(new_form.form_id),
              params: {
                form_data: { greeting: 'Hello!' },
                metadata: new_form.metadata
              }.to_json,
              headers: { 'CONTENT_TYPE' => 'application/json' }
          # Checking key present, it will be false regardless due to prefill not running
          metadata = JSON.parse(response.body)['data']['attributes']['metadata']
          expect(metadata.key?('new_conditions_workflow')).to be(true)
          expect(response).to have_http_status(:ok)
        end

        it 'does not add new conditions workflow metadata if flipper disabled' do
          allow(Flipper).to receive(:enabled?).with(flipper_new_conditions).and_return(false)
          put v0_disability_compensation_in_progress_form_url(new_form.form_id),
              params: {
                form_data: { greeting: 'Hello!' },
                metadata: new_form.metadata
              }.to_json,
              headers: { 'CONTENT_TYPE' => 'application/json' }
          metadata = JSON.parse(response.body)['data']['attributes']['metadata']
          expect(metadata.key?('new_conditions_workflow')).to be(false)
          expect(response).to have_http_status(:ok)
        end

        context 'when flipper is enabled for new conditions workflow metadata' do
          before do
            allow(Flipper).to receive(:enabled?).with(flipper_new_conditions).and_return(true)
          end

          it 'sets new_conditions_workflow to true when disability_comp_new_conditions_workflow is true' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!', disability_comp_new_conditions_workflow: true },
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['new_conditions_workflow']).to be(true)
            expect(response).to have_http_status(:ok)
          end

          it 'sets new_conditions_workflow to false when disability_comp_new_conditions_workflow is false' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!', disability_comp_new_conditions_workflow: false },
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['new_conditions_workflow']).to be(false)
            expect(response).to have_http_status(:ok)
          end

          it 'defaults new_conditions_workflow to false when not present in form_data' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!' },
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['new_conditions_workflow']).to be(false)
            expect(response).to have_http_status(:ok)
          end

          it 'handles form_data as a JSON string' do
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: {
                  form_data: { greeting: 'Hello!', disability_comp_new_conditions_workflow: true }.to_json,
                  metadata: new_form.metadata
                }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }

            metadata = JSON.parse(response.body)['data']['attributes']['metadata']
            expect(metadata['new_conditions_workflow']).to be(true)
            expect(response).to have_http_status(:ok)
          end
        end

        describe 'condition/evidence delta metrics' do
          let(:ipf_metadata) { { returnUrl: '/conditions/summary' } }

          def put_form(form_data, metadata: ipf_metadata)
            put v0_disability_compensation_in_progress_form_url(new_form.form_id),
                params: { form_data:, metadata: }.to_json,
                headers: { 'CONTENT_TYPE' => 'application/json' }
          end

          def loaded_metadata
            InProgressForm.form_for_user(new_form.form_id, update_user).metadata
          end

          before do
            allow(Rails.logger).to receive(:info).and_call_original
          end

          describe 'reached-evidence gate' do
            it 'suppresses all emissions before Supporting Evidence is reached' do
              put_form({ new_disabilities: [] })
              put_form({ new_disabilities: [{ condition: 'asthma' }] })

              expect(Rails.logger).not_to have_received(:info)
                .with('Form526 conditions evidence delta event', anything)
              expect(loaded_metadata['had_unpaired_condition_add']).to be(false)
              expect(loaded_metadata['had_unpaired_condition_removal']).to be(false)
            end

            it 'opens the gate when formData carries a supporting-evidence marker' do
              put_form({ new_disabilities: [], 'view:has_evidence': true })

              put_form({ new_disabilities: [{ condition: 'asthma' }], 'view:has_evidence': true })
              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'condition_added'))
            end

            it 'opens the gate when formData carries selectable_evidence_types marker' do
              put_form({ new_disabilities: [], 'view:selectable_evidence_types': [] })

              put_form({ new_disabilities: [{ condition: 'asthma' }], 'view:selectable_evidence_types': [] })
              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'condition_added'))
            end
          end

          describe 'condition events' do
            before do
              put_form({ new_disabilities: [], 'view:has_evidence': true })
            end

            it 'emits condition_added when the count increases' do
              put_form({ new_disabilities: [{ condition: 'asthma' }], 'view:has_evidence': true })

              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'condition_added'))
              expect(loaded_metadata['had_unpaired_condition_add']).to be(true)
            end

            it 'emits condition_removed when the count decreases' do
              put_form(
                {
                  new_disabilities: [{ condition: 'asthma' }, { condition: 'bronchitis' }],
                  'view:has_evidence': true
                }
              )
              put_form({ new_disabilities: [{ condition: 'asthma' }], 'view:has_evidence': true })

              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'condition_removed'))
              expect(loaded_metadata['had_unpaired_condition_removal']).to be(true)
            end
          end

          describe 'evidence-add pairing' do
            before do
              put_form({ new_disabilities: [], 'view:has_evidence': true })
            end

            it 'emits evidence_added only when paired with an unpaired condition_added' do
              put_form({ new_disabilities: [], attachments: [], 'view:has_evidence': true })
              # condition_added opens the latch
              put_form({ new_disabilities: [{ condition: 'asthma' }], attachments: [], 'view:has_evidence': true })
              # evidence_added consumes the latch
              put_form({ new_disabilities: [{ condition: 'asthma' }],
                         attachments: [{ name: 'file_from_private_facility' }],
                         'view:has_evidence': true })

              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'evidence_added'))
              expect(loaded_metadata['had_unpaired_condition_add']).to be(false)
            end

            it 'suppresses evidence_added when no unpaired condition_added is open' do
              # No condition ever added — evidence add is orphaned.
              put_form({ attachments: [], 'view:has_evidence': true })
              put_form({ attachments: [{ name: 'file_from_private_facility' }], 'view:has_evidence': true })

              expect(Rails.logger).not_to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'evidence_added'))
            end

            it 'suppresses a second evidence_added within the same condition-add cycle' do
              put_form({ new_disabilities: [{ condition: 'asthma' }], attachments: [], 'view:has_evidence': true })
              # 1st evidence add: pairs with condition_added, emits.
              put_form({ new_disabilities: [{ condition: 'asthma' }],
                         attachments: [{ name: 'file_from_private_facility' }],
                         'view:has_evidence': true })
              # 2nd evidence add: no new condition_added, so suppressed.
              put_form(
                { new_disabilities: [{ condition: 'asthma' }],
                  attachments: [{ name: 'file_from_private_facility' }, { name: 'file_from_private_facility_2' }],
                  'view:has_evidence': true }
              )

              # Exactly one evidence_added across all three PUTs.
              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'evidence_added')).once
            end

            it 're-opens the latch when a new condition is added, allowing another paired evidence_added' do
              put_form({ new_disabilities: [{ condition: 'asthma' }], attachments: [], 'view:has_evidence': true })
              # 1st condition_added arms + 1st evidence_added consumes latch.
              put_form({ new_disabilities: [{ condition: 'asthma' }],
                         attachments: [{ name: 'file_from_private_facility' }],
                         'view:has_evidence': true })
              # 2nd condition_added re-arms + 2nd evidence_added consumes.
              put_form(
                { new_disabilities: [{ condition: 'asthma' }, { condition: 'bronchitis' }],
                  attachments: [{ name: 'file_from_private_facility' }, { name: 'file_from_private_facility_2' }],
                  'view:has_evidence': true }
              )

              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'condition_added')).twice
              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'evidence_added')).twice
            end
          end

          describe 'evidence-remove pairing' do
            before do
              put_form({ new_disabilities: [], 'view:has_evidence': true })
            end

            it 'emits evidence_removed only when there is an unpaired condition_removed' do
              put_form({ new_disabilities: [{ condition: 'asthma' }],
                         attachments: [{ name: 'file_from_private_facility' }],
                         'view:has_evidence': true })
              put_form({
                         new_disabilities: [],
                         attachments: [{ name: 'file_from_private_facility' }],
                         'view:has_evidence': true
                       })
              put_form({ new_disabilities: [], attachments: [], 'view:has_evidence': true })

              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'evidence_removed'))
              expect(loaded_metadata['had_unpaired_condition_removal']).to be(false)
            end

            it 'suppresses evidence_removed when there is no unpaired condition_removed' do
              put_form({ new_disabilities: [{ condition: 'asthma' }],
                         attachments: [{ name: 'file_from_private_facility' }],
                         'view:has_evidence': true })
              put_form({ new_disabilities: [{ condition: 'asthma' }], attachments: [], 'view:has_evidence': true })

              expect(Rails.logger).not_to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'evidence_removed'))
            end

            it 'suppresses a second, unrelated evidence_removed after the latch is consumed' do
              put_form({ new_disabilities: [{ condition: 'asthma' }], attachments:
                [{ name: 'file_from_private_facility' }, { name: 'file_from_private_facility_2' }],
                         'view:has_evidence': true })

              # condition is removed, opening the latch
              put_form({ new_disabilities: [],
                         attachments: [{ name: 'file_from_private_facility' },
                                       { name: 'file_from_private_facility_2' }],
                         'view:has_evidence': true })
              # a file is removed
              put_form({
                         new_disabilities: [],
                         attachments: [{ name: 'file_from_private_facility' }],
                         'view:has_evidence': true
                       })
              # a second file is removed
              put_form({ new_disabilities: [], attachments: [], 'view:has_evidence': true })

              # exactly one evidence_removed emitted
              expect(Rails.logger).to have_received(:info)
                .with('Form526 conditions evidence delta event', hash_including(event: 'evidence_removed')).once
            end
          end

          it 'swallows internal errors so that they do not disrupt the save' do
            allow(Rails.logger).to receive(:info)
              .with('Form526 conditions evidence delta event', anything)
              .and_raise(StandardError, 'lorem')

            expect do
              put_form({ new_disabilities: [{ condition: 'asthma' }], 'view:has_evidence': true })
            end.not_to raise_error
            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'without a user' do
        describe '#show' do
          let(:in_progress_form) { create(:in_progress_form) }

          it 'returns a 401' do
            get v0_disability_compensation_in_progress_form_url(in_progress_form.form_id), params: nil

            expect(response).to have_http_status(:unauthorized)
          end
        end
      end
    end
  end
end
