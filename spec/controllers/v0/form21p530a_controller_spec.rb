# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::Form21p530aController, type: :controller do
  let(:valid_payload) { JSON.parse(Rails.root.join('spec', 'fixtures', 'form21p530a', 'valid_form.json').read) }
  let(:user) { create(:user, :loa1) }

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:form_530a_enabled, anything).and_return(true)
  end

  context 'when unauthenticated' do
    context 'when aquia_bio_auth_required is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:aquia_bio_auth_required, anything).and_return(true)
      end

      describe 'POST #create' do
        it 'requires authentication' do
          post(:create, body: valid_payload.to_json, as: :json)
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'when aquia_bio_auth_required is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:aquia_bio_auth_required, anything).and_return(false)
      end

      describe 'POST #create' do
        it 'allows unauthenticated access' do
          post(:create, body: valid_payload.to_json, as: :json)
          expect(response).to have_http_status(:ok)
        end
      end

      describe 'GET #download_pdf' do
        let(:temp_file_path) { '/tmp/test_pdf.pdf' }
        let(:claim_guid) { SecureRandom.uuid }
        let(:claim) do
          instance_double(SavedClaim::Form21p530a,
                          guid: claim_guid,
                          veteran_name: 'John Doe',
                          to_pdf: temp_file_path)
        end
        let(:monitor) { instance_double(Form21p530a::Monitor) }

        before do
          allow(SavedClaim::Form21p530a).to receive(:find_by!).with(guid: claim_guid).and_return(claim)
          allow(Form21p530a::Monitor).to receive(:new).and_return(monitor)
          allow(monitor).to receive(:track_request_code)
          allow(monitor).to receive(:track_pdf_generation_success)
          allow(monitor).to receive(:track_pdf_generation_failure)
          allow(File).to receive(:read).and_call_original
          allow(File).to receive(:read).with(temp_file_path).and_return('PDF_CONTENT')
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(temp_file_path).and_return(true)
          allow(File).to receive(:delete).and_call_original
          allow(File).to receive(:delete).with(temp_file_path)
        end

        it 'allows unauthenticated access' do
          get(:download_pdf, params: { guid: claim_guid })
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  context 'when authenticated' do
    before do
      sign_in_as(user)
    end

    describe 'POST #create' do
      it 'returns expected response structure' do
        post(:create, body: valid_payload.to_json, as: :json)

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['data']['type']).to eq('saved_claims')
        expect(json['data']['attributes']['form']).to eq('21P-530A')
        expect(json['data']['attributes']['confirmation_number']).to be_present
        expect(json['data']['attributes']['submitted_at']).to be_present
        expect(json['data']['attributes']['guid']).to be_present
        expect(json['data']['attributes']['regional_office']).to be_an(Array)
      end

      it 'returns a unique confirmation number for each request' do
        post(:create, body: valid_payload.to_json, as: :json)
        first_confirmation = JSON.parse(response.body)['data']['attributes']['confirmation_number']

        post(:create, body: valid_payload.to_json, as: :json)
        second_confirmation = JSON.parse(response.body)['data']['attributes']['confirmation_number']

        expect(first_confirmation).not_to eq(second_confirmation)
      end

      it 'returns a valid UUID as confirmation number' do
        post(:create, body: valid_payload.to_json, as: :json)

        confirmation = JSON.parse(response.body).dig('data', 'attributes', 'confirmation_number')
        expect(confirmation).to be_a_uuid
      end

      it 'returns ISO 8601 formatted timestamp' do
        post(:create, body: valid_payload.to_json, as: :json)

        submitted_at = JSON.parse(response.body).dig('data', 'attributes', 'submitted_at')
        expect { DateTime.iso8601(submitted_at) }.not_to raise_error
      end

      it 'queues Lighthouse submission job' do
        expect(Lighthouse::SubmitBenefitsIntakeClaim).to receive(:perform_async).with(anything)
        post(:create, body: valid_payload.to_json, as: :json)
      end

      describe 'monitoring' do
        let(:monitor) { instance_double(Form21p530a::Monitor) }

        before do
          allow(Form21p530a::Monitor).to receive(:new).and_return(monitor)
          allow(monitor).to receive(:track_submission_begun)
          allow(monitor).to receive(:track_submission_success)
          allow(monitor).to receive(:track_submission_failure)
        end

        it 'tracks submission begun' do
          expect(monitor).to receive(:track_submission_begun).with(
            an_instance_of(SavedClaim::Form21p530a),
            user_uuid: user.uuid
          )
          post(:create, body: valid_payload.to_json, as: :json)
        end

        it 'tracks submission success' do
          expect(monitor).to receive(:track_submission_success).with(
            an_instance_of(SavedClaim::Form21p530a),
            user_uuid: user.uuid
          )
          post(:create, body: valid_payload.to_json, as: :json)
        end

        context 'with authenticated user' do
          it 'tracks submission with user_uuid' do
            expect(monitor).to receive(:track_submission_begun).with(
              an_instance_of(SavedClaim::Form21p530a),
              user_uuid: user.uuid
            )
            expect(monitor).to receive(:track_submission_success).with(
              an_instance_of(SavedClaim::Form21p530a),
              user_uuid: user.uuid
            )
            post(:create, body: valid_payload.to_json, as: :json)
          end
        end

        context 'on validation failure' do
          let(:invalid_payload) { { veteranInformation: { fullName: { first: 'OnlyFirst' } } } }

          it 'tracks submission begun even when save fails' do
            expect(monitor).to receive(:track_submission_begun)
            post(:create, body: invalid_payload.to_json, as: :json)
          end

          it 'tracks submission failure when claim save fails' do
            expect(monitor).to receive(:track_submission_failure)
            post(:create, body: invalid_payload.to_json, as: :json)
          end
        end
      end

      context 'with 3-character country code' do
        let(:payload_with_3char_country) do
          payload = valid_payload.deep_dup
          payload['burialInformation']['recipientOrganization']['address']['country'] = 'USA'
          payload
        end

        it 'transforms 3-character country code to 2-character' do
          post(:create, body: payload_with_3char_country.to_json, as: :json)
          expect(response).to have_http_status(:ok)

          # Verify the claim was created successfully (transformation happened)
          json = JSON.parse(response.body)
          expect(json['data']['attributes']['confirmation_number']).to be_present
        end
      end

      context 'with invalid country code' do
        let(:payload_with_invalid_country) do
          payload = valid_payload.deep_dup
          payload['burialInformation']['recipientOrganization']['address']['country'] = 'XX'
          payload
        end

        it 'rejects invalid 2-character country code' do
          post(:create, body: payload_with_invalid_country.to_json, as: :json)

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['errors']).to be_present
          expect(json['errors'].first['detail']).to include("'XX' is not a valid country code")
        end

        it 'rejects invalid 3-character country code' do
          payload = valid_payload.deep_dup
          payload['burialInformation']['recipientOrganization']['address']['country'] = 'ZZZ'

          post(:create, body: payload.to_json, as: :json)

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['errors']).to be_present
          expect(json['errors'].first['detail']).to include("'ZZZ' is not a valid country code")
        end
      end

      context 'when feature flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:form_530a_enabled, anything).and_return(false)
        end

        it 'returns 404 Not Found (routing error)' do
          post(:create, body: valid_payload.to_json, as: :json)
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'with invalid form data' do
        let(:invalid_payload) do
          {
            veteranInformation: {
              fullName: { first: 'OnlyFirst' }
            }
          }
        end

        it 'returns validation errors' do
          post(:create, body: invalid_payload.to_json, as: :json)

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['errors']).to be_present
        end
      end

      context 'InProgressForm cleanup' do
        let!(:in_progress_form) { create(:in_progress_form, form_id: '21P-530A', user_account: user.user_account) }

        it 'deletes the InProgressForm after successful submission' do
          expect do
            post(:create, body: valid_payload.to_json, as: :json)
          end.to change(InProgressForm, :count).by(-1)

          expect(response).to have_http_status(:ok)
          expect(InProgressForm.find_by(id: in_progress_form.id)).to be_nil
        end

        it 'does not delete IPF if submission fails' do
          invalid_payload = { veteranInformation: { fullName: { first: 'OnlyFirst' } } }

          expect do
            post(:create, body: invalid_payload.to_json, as: :json)
          end.not_to change(InProgressForm, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe 'GET #download_pdf' do
      let(:claim) do
        claim = SavedClaim::Form21p530a.new(form: valid_payload.to_json)
        claim.save!(validate: false)
        claim
      end
      let(:pdf_content) { 'PDF_BINARY_CONTENT' }
      let(:temp_file_path) { '/tmp/test_pdf.pdf' }
      let(:monitor) { instance_double(Form21p530a::Monitor) }

      before do
        allow(Form21p530a::Monitor).to receive(:new).and_return(monitor)
        allow(monitor).to receive(:track_request_code)
        allow(monitor).to receive(:track_pdf_generation_success)
        allow(monitor).to receive(:track_pdf_generation_failure)
        allow_any_instance_of(SavedClaim::Form21p530a).to receive(:after_create_metrics)
        allow_any_instance_of(SavedClaim::Form21p530a).to receive(:to_pdf).and_return(temp_file_path)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(temp_file_path).and_return(pdf_content)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(temp_file_path).and_return(true)
        allow(File).to receive(:delete).and_call_original
        allow(File).to receive(:delete).with(temp_file_path)
      end

      it 'generates and downloads PDF' do
        get(:download_pdf, params: { guid: claim.guid })

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Type']).to eq('application/pdf')
        expect(response.body).to eq(pdf_content)
      end

      it 'includes proper filename with veteran name' do
        get(:download_pdf, params: { guid: claim.guid })

        expect(response.headers['Content-Disposition']).to include('attachment')
        expect(response.headers['Content-Disposition']).to include('21P-530a_John_Doe.pdf')
      end

      it 'returns 404 for invalid guid' do
        get(:download_pdf, params: { guid: SecureRandom.uuid })
        expect(response).to have_http_status(:not_found)
      end

      it 'deletes temporary PDF file after sending' do
        expect(File).to receive(:delete).with(temp_file_path)
        get(:download_pdf, params: { guid: claim.guid })
      end

      it 'tracks PDF generation success' do
        expect(monitor).to receive(:track_pdf_generation_success)
          .with(kind_of(Time), hash_including(user_uuid: user.uuid, claim_guid: claim.guid))

        get(:download_pdf, params: { guid: claim.guid })
      end

      it 'tracks PDF generation failure with claim_guid' do
        allow_any_instance_of(SavedClaim::Form21p530a).to receive(:to_pdf).and_raise(StandardError, 'PDF error')
        expect(monitor).to receive(:track_pdf_generation_failure)
          .with(kind_of(StandardError), hash_including(user_uuid: user.uuid, claim_guid: claim.guid))

        get(:download_pdf, params: { guid: claim.guid })
        expect(response).to have_http_status(:internal_server_error)
      end

      context 'when feature flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:form_530a_enabled, anything).and_return(false)
        end

        it 'returns 404 Not Found (routing error)' do
          get(:download_pdf, params: { guid: claim.guid })
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end
