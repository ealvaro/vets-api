# frozen_string_literal: true

require_relative '../../../rails_helper'

RSpec.describe AccreditedRepresentativePortal::V0::InProgressFormsController, type: :request do
  let(:representative_user) { create(:representative_user) }
  let(:form_id) { '21a' }
  let(:headers) { { 'Content-Type' => 'application/json' } }

  before do
    login_as(representative_user)
  end

  describe 'GET /in_progress_forms/:id' do
    context 'when the form exists' do
      it 'returns the form data and metadata' do
        travel_to Time.utc(2022, 3, 4, 5, 6, 7) do
          create(
            :in_progress_form,
            user_uuid: representative_user.uuid,
            form_data: { field: 'value' },
            form_id:,
            metadata: { version: 1, returnUrl: 'foo.com' }
          )

          get("/accredited_representative_portal/v0/in_progress_forms/#{form_id}")

          expect(response).to have_http_status(:ok)
          expect(parsed_response).to eq(
            {
              'formData' => { 'field' => 'value' },
              'metadata' => {
                'version' => 1,
                'returnUrl' => 'foo.com',
                'createdAt' => 1_646_370_367,
                'expiresAt' => 1_651_554_367,
                'lastUpdated' => 1_646_370_367,
                'inProgressFormId' => InProgressForm.last.id
              }
            }
          )
        end
      end
    end

    context 'when no matching form exists' do
      it 'returns an empty object' do
        get("/accredited_representative_portal/v0/in_progress_forms/#{form_id}")

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq({}.to_json)
      end
    end
  end

  describe 'PUT /in_progress_forms/:id' do
    context 'when no form exists yet' do
      it 'creates a new form and returns the serialized record' do
        travel_to Time.utc(2022, 3, 5, 5, 6, 7) do
          put(
            "/accredited_representative_portal/v0/in_progress_forms/#{form_id}",
            params: { 'formData' => { anotherField: 'foo' } }.to_json,
            headers:
          )

          expect(response).to have_http_status(:ok)
          expect(parsed_response).to eq(
            {
              'data' => {
                'id' => '',
                'type' => 'in_progress_forms',
                'attributes' => {
                  'formId' => '21a',
                  'createdAt' => '2022-03-05T05:06:07.000Z',
                  'updatedAt' => '2022-03-05T05:06:07.000Z',
                  'metadata' => {
                    'createdAt' => 1_646_456_767,
                    'expiresAt' => 1_651_640_767,
                    'lastUpdated' => 1_646_456_767,
                    'inProgressFormId' => InProgressForm.last.id
                  }
                }
              }
            }
          )
          expect(InProgressForm.where(form_id:, user_uuid: representative_user.uuid).count).to eq(1)
        end
      end
    end

    context 'when a form already exists' do
      it 'preserves createdAt while advancing updatedAt, lastUpdated, and expiresAt' do
        travel_to(Time.utc(2022, 3, 5, 5, 6, 7)) do
          create(
            :in_progress_form,
            user_uuid: representative_user.uuid,
            form_data: { field: 'original' },
            form_id:
          )
        end

        travel_to Time.utc(2022, 3, 6, 5, 6, 7) do
          put(
            "/accredited_representative_portal/v0/in_progress_forms/#{form_id}",
            params: { 'formData' => { field: 'updated' } }.to_json,
            headers:
          )

          expect(response).to have_http_status(:ok)
          expect(parsed_response).to eq(
            {
              'data' => {
                'id' => '',
                'type' => 'in_progress_forms',
                'attributes' => {
                  'formId' => '21a',
                  'createdAt' => '2022-03-05T05:06:07.000Z',
                  'updatedAt' => '2022-03-06T05:06:07.000Z',
                  'metadata' => {
                    'createdAt' => 1_646_456_767,
                    'expiresAt' => 1_651_727_167,
                    'lastUpdated' => 1_646_543_167,
                    'inProgressFormId' => InProgressForm.last.id
                  }
                }
              }
            }
          )
          expect(InProgressForm.where(form_id:, user_uuid: representative_user.uuid).count).to eq(1)
        end

        get("/accredited_representative_portal/v0/in_progress_forms/#{form_id}")
        expect(parsed_response.dig('formData', 'field')).to eq('updated')
      end
    end
  end

  describe 'DELETE /in_progress_forms/:id' do
    context 'when the form exists' do
      it 'destroys the form and returns 204' do
        create(
          :in_progress_form,
          user_uuid: representative_user.uuid,
          form_data: { field: 'value' },
          form_id:
        )

        delete("/accredited_representative_portal/v0/in_progress_forms/#{form_id}")

        expect(response).to have_http_status(:no_content)
        expect(InProgressForm.where(form_id:, user_uuid: representative_user.uuid).count).to eq(0)
      end
    end

    context 'when no matching form exists' do
      it 'returns 404 not found' do
        delete("/accredited_representative_portal/v0/in_progress_forms/#{form_id}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'feature flag accredited_representative_portal_form_21a' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:accredited_representative_portal_form_21a)
        .and_return(false)
    end

    it 'blocks GET with 404 when the flag is disabled' do
      get("/accredited_representative_portal/v0/in_progress_forms/#{form_id}")
      expect(response).to have_http_status(:not_found)
    end

    it 'blocks PUT with 404 when the flag is disabled' do
      put(
        "/accredited_representative_portal/v0/in_progress_forms/#{form_id}",
        params: { 'formData' => {} }.to_json,
        headers:
      )
      expect(response).to have_http_status(:not_found)
    end

    it 'blocks DELETE with 404 when the flag is disabled' do
      delete("/accredited_representative_portal/v0/in_progress_forms/#{form_id}")
      expect(response).to have_http_status(:not_found)
    end
  end
end
