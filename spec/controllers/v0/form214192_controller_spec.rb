# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::Form214192Controller, type: :controller do
  let(:monitor) { instance_double(Form214192::Monitor) }
  let(:valid_payload) { JSON.parse(Rails.root.join('spec', 'fixtures', 'form214192', 'valid_form.json').read) }
  let(:form_data) do
    JSON.parse(Rails.root.join('spec', 'fixtures', 'pdf_fill', '21-4192', 'simple.json').read)
  end
  let(:user) { create(:user, :loa1) }

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:form_4192_enabled, anything).and_return(true)
    allow(Form214192::Monitor).to receive(:new).and_return(monitor)
    allow(monitor).to receive(:track_submission_begun)
    allow(monitor).to receive(:track_submission_success)
    allow(monitor).to receive(:track_submission_failure)
    allow(monitor).to receive(:track_request_code)
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
        expect(json['data']['attributes']['form']).to eq('21-4192')
        expect(json['data']['attributes']['confirmation_number']).to be_present
        expect(json['data']['attributes']['submitted_at']).to be_present
        expect(json['data']['attributes']['guid']).to be_present
        expect(json['data']['attributes']['regional_office']).to eq([])
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

      context 'when feature flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:form_4192_enabled, anything).and_return(false)
        end

        it 'returns 404 Not Found (routing error)' do
          post(:create, body: valid_payload.to_json, as: :json)
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'InProgressForm cleanup' do
        let!(:in_progress_form) { create(:in_progress_form, form_id: '21-4192', user_account: user.user_account) }

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

      describe 'monitoring' do
        it 'tracks submission begun when claim is created' do
          expect(monitor).to receive(:track_submission_begun) do |claim|
            expect(claim).to be_a(SavedClaim::Form214192)
          end

          post(:create, body: valid_payload.to_json, as: :json)
        end

        it 'tracks submission success when claim saves successfully' do
          expect(monitor).to receive(:track_submission_success) do |claim|
            expect(claim).to be_a(SavedClaim::Form214192)
            expect(claim.persisted?).to be true
          end

          post(:create, body: valid_payload.to_json, as: :json)
        end

        it 'tracks submission failure when validation fails' do
          invalid_payload = { veteranInformation: { fullName: { first: 'OnlyFirst' } } }

          expect(monitor).to receive(:track_submission_failure) do |claim, error|
            expect(claim).to be_a(SavedClaim::Form214192)
            expect(error.message).to eq('Validation failed')
          end

          post(:create, body: invalid_payload.to_json, as: :json)
        end
      end
    end

    describe 'GET #download_pdf' do
      let(:claim) do
        SavedClaim::Form214192.create!(
          form: form_data.to_json,
          form_id: '21-4192',
          user_account: user.user_account
        )
      end
      let(:pdf_content) { 'PDF_BINARY_CONTENT' }
      let(:temp_file_path) { '/tmp/test_pdf.pdf' }
      let(:monitor) { instance_double(Form214192::Monitor) }

      before do
        allow(Flipper).to receive(:enabled?).with(:form_4192_enabled, anything).and_return(true)
        allow(Form214192::Monitor).to receive(:new).and_return(monitor)
        allow(monitor).to receive(:track_request_code)
        allow(monitor).to receive(:track_pdf_generation_success)
        allow(monitor).to receive(:track_pdf_generation_failure)

        # Stub after_create callback to prevent metrics tracking during claim creation
        allow_any_instance_of(SavedClaim::Form214192).to receive(:after_create_metrics)

        # Stub to_pdf to return the temp file path
        allow_any_instance_of(SavedClaim::Form214192).to receive(:to_pdf).and_return(temp_file_path)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(temp_file_path).and_return(pdf_content)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(temp_file_path).and_return(true)
        allow(File).to receive(:delete).and_call_original
        allow(File).to receive(:delete).with(temp_file_path)
      end

      it 'generates and downloads PDF by GUID' do
        get(:download_pdf, params: { guid: claim.guid })

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Type']).to eq('application/pdf')
        expect(response.body).to eq(pdf_content)
      end

      it 'includes proper filename with veteran name' do
        get(:download_pdf, params: { guid: claim.guid })

        expect(response.headers['Content-Disposition']).to include('attachment')
        expect(response.headers['Content-Disposition']).to include('21-4192_')
        expect(response.headers['Content-Disposition']).to include('21-4192_John_Doe.pdf')
      end

      it 'uses same filename for same claim' do
        get(:download_pdf, params: { guid: claim.guid })
        first_filename = response.headers['Content-Disposition']

        get(:download_pdf, params: { guid: claim.guid })
        second_filename = response.headers['Content-Disposition']

        expect(first_filename).to eq(second_filename)
      end

      it 'deletes temporary PDF file after sending' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(temp_file_path).and_return(true)
        expect(File).to receive(:delete).with(temp_file_path)
        get(:download_pdf, params: { guid: claim.guid })
      end

      it 'deletes temporary file even when file read fails' do
        allow(File).to receive(:read).with(temp_file_path).and_raise(StandardError, 'Read error')
        # File should still be deleted in ensure block (file was created by Filler)
        expect(File).to receive(:delete).with(temp_file_path)

        get(:download_pdf, params: { guid: claim.guid })
        expect(response).to have_http_status(:internal_server_error)

        json = JSON.parse(response.body)
        expect(json['errors']).to be_present
        expect(json['errors'].first['title']).to eq('PDF Generation Failed')
      end

      it 'returns 404 for invalid GUID' do
        get(:download_pdf, params: { guid: SecureRandom.uuid })
        expect(response).to have_http_status(:not_found)
      end

      describe 'monitoring' do
        it 'tracks PDF generation success' do
          expect(monitor).to receive(:track_pdf_generation_success).with(kind_of(Time),
                                                                         hash_including(user_uuid: user.uuid,
                                                                                        claim_guid: claim.guid))

          get(:download_pdf, params: { guid: claim.guid })
        end

        it 'tracks PDF generation failure for errors' do
          allow_any_instance_of(SavedClaim::Form214192).to receive(:to_pdf).and_raise(StandardError, 'PDF error')
          expect(monitor).to receive(:track_pdf_generation_failure).with(kind_of(StandardError),
                                                                         hash_including(user_uuid: user.uuid,
                                                                                        claim_guid: claim.guid))

          get(:download_pdf, params: { guid: claim.guid })
          expect(response).to have_http_status(:internal_server_error)
        end
      end

      context 'when feature flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:form_4192_enabled, anything).and_return(false)
        end

        it 'returns 404 Not Found (routing error)' do
          get(:download_pdf, params: { guid: claim.guid })
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'with 30-character street2 address' do
        let(:payload_with_max_street2) do
          payload = form_data.deep_dup
          payload['employmentInformation']['employerAddress']['street2'] = 'B' * 30
          payload
        end

        let(:claim) do
          SavedClaim::Form214192.create!(
            form: payload_with_max_street2.to_json,
            form_id: '21-4192',
            user_account: user.user_account
          )
        end

        it 'accepts street2 with exactly 30 characters' do
          get(:download_pdf, params: { guid: claim.guid })

          expect(response).to have_http_status(:ok)
          expect(response.headers['Content-Type']).to eq('application/pdf')
        end
      end
    end

    describe 'address field validation' do
      context 'with extended street2 values' do
        let(:payload_with_long_street2) do
          payload = valid_payload.deep_dup
          # Set street2 to a value longer than old 5-char limit but within new 30-char limit
          payload['veteranInformation']['address']['street2'] = 'Apartment Suite 10B'
          payload['employmentInformation']['employerAddress']['street2'] = 'Building A, Floor 3'
          payload
        end

        it 'accepts street2 values up to 30 characters for form submission' do
          post(:create, body: payload_with_long_street2.to_json, as: :json)

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json['data']['attributes']['confirmation_number']).to be_present
        end
      end

      context 'with street2 values exceeding 30 characters' do
        let(:payload_with_too_long_street2) do
          payload = valid_payload.deep_dup
          # Set street2 to 31 characters (exceeds new maximum)
          payload['veteranInformation']['address']['street2'] = 'A' * 31
          payload
        end

        it 'rejects street2 values exceeding 30 characters for form submission' do
          post(:create, body: payload_with_too_long_street2.to_json, as: :json)

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['errors']).to be_present
        end
      end
    end
  end
end
