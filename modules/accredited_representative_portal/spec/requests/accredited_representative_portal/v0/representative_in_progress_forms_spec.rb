# frozen_string_literal: true

require_relative '../../../rails_helper'

RSpec.describe 'AccreditedRepresentativePortal::V0::RepresentativeInProgressForms', type: :request do
  let(:rep_user) { create(:representative_user) }
  let(:veteran_icn) { '1234567890V123456' }
  let(:claimant_id) { AccreditedRepresentativePortal::IcnTemporaryIdentifier.save_icn(veteran_icn).id }
  let(:form_id) { '21-686c-ARP' }
  let(:base_path) { "/accredited_representative_portal/v0/representative_in_progress_forms/#{form_id}" }

  describe 'unauthenticated' do
    it 'returns 401 for show' do
      get "#{base_path}?claimant_id=#{claimant_id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for update' do
      put "#{base_path}?claimant_id=#{claimant_id}", params: { formData: '{}' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for destroy' do
      delete "#{base_path}?claimant_id=#{claimant_id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'authenticated' do
    before { login_as(rep_user) }

    context 'when the accredited_representative_portal_submit_686c_v2 flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(
          :accredited_representative_portal_submit_686c_v2
        ).and_return false
      end

      it 'returns 404 for show' do
        get "#{base_path}?claimant_id=#{claimant_id}"
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 for update' do
        put "#{base_path}?claimant_id=#{claimant_id}", params: { formData: '{}' }
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 for destroy' do
        delete "#{base_path}?claimant_id=#{claimant_id}"
        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'GET show' do
      context 'without claimant_id' do
        it 'returns 422' do
          get base_path
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when no form exists' do
        it 'returns empty object' do
          get "#{base_path}?claimant_id=#{claimant_id}"
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq({})
        end
      end

      context 'when a form exists for this rep and veteran' do
        let!(:form) do
          create(:representative_in_progress_form,
                 rep_user_account: rep_user.user_account,
                 veteran_icn:,
                 form_id:)
        end

        it 'returns the form data and metadata' do
          get "#{base_path}?claimant_id=#{claimant_id}"
          expect(response).to have_http_status(:ok)
          body = response.parsed_body
          expect(body['formData']).to be_present
          expect(body['metadata']).to include('inProgressFormId' => form.id)
        end
      end

      context 'when a form exists for a different rep' do
        before do
          create(:representative_in_progress_form,
                 rep_user_account: create(:user_account),
                 veteran_icn:,
                 form_id:)
        end

        it 'returns empty object' do
          get "#{base_path}?claimant_id=#{claimant_id}"
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq({})
        end
      end
    end

    describe 'PUT update' do
      let(:form_data) { { veteranInformation: { firstName: 'Jane' } }.to_json }
      let(:metadata) { { version: 1, returnUrl: '/representative/686c/veteran-information' } }

      context 'without claimant_id' do
        it 'returns 422' do
          put base_path, params: { formData: form_data, metadata: }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when no form exists' do
        it 'creates a new form and returns it' do
          expect do
            put "#{base_path}?claimant_id=#{claimant_id}",
                params: { formData: form_data, metadata: }
          end.to change(AccreditedRepresentativePortal::RepresentativeInProgressForm, :count).by(1)

          expect(response).to have_http_status(:ok)
          attributes = response.parsed_body.dig('data', 'attributes')
          expect(attributes['formId']).to eq(form_id)
          expect(attributes['claimantId']).to eq(claimant_id)
        end
      end

      context 'when a form already exists' do
        let!(:existing_form) do
          create(:representative_in_progress_form,
                 rep_user_account: rep_user.user_account,
                 veteran_icn:,
                 form_id:)
        end

        it 'updates the existing form without creating a new one' do
          expect do
            put "#{base_path}?claimant_id=#{claimant_id}",
                params: { formData: form_data, metadata: }
          end.not_to change(AccreditedRepresentativePortal::RepresentativeInProgressForm, :count)

          expect(response).to have_http_status(:ok)
          expect(existing_form.reload.form_data).to eq(form_data)
        end
      end

      context 'when the same rep has in-progress drafts for two different claimants' do
        let(:veteran_a_icn) { '1111111111V111111' }
        let(:veteran_b_icn) { '2222222222V222222' }
        let(:claimant_b_id) { AccreditedRepresentativePortal::IcnTemporaryIdentifier.save_icn(veteran_b_icn).id }

        let!(:draft_a) do
          create(:representative_in_progress_form,
                 rep_user_account: rep_user.user_account,
                 veteran_icn: veteran_a_icn,
                 form_id:,
                 form_data: { veteranInformation: { firstName: 'ClaimantA' } }.to_json)
        end

        it "saving claimant B's draft does not overwrite claimant A's draft" do
          expect do
            put "#{base_path}?claimant_id=#{claimant_b_id}",
                params: { formData: { veteranInformation: { firstName: 'ClaimantB' } }.to_json, metadata: }
          end.to change(AccreditedRepresentativePortal::RepresentativeInProgressForm, :count).by(1)

          expect(response).to have_http_status(:ok)

          draft_a.reload
          draft_b = AccreditedRepresentativePortal::RepresentativeInProgressForm.for_rep_and_veteran(
            form_id, rep_user.user_account_uuid, veteran_b_icn
          )

          expect(draft_a.veteran_icn).to eq(veteran_a_icn)
          expect(JSON.parse(draft_a.form_data)['veteranInformation']['firstName']).to eq('ClaimantA')

          expect(draft_b).to be_present
          expect(draft_b.veteran_icn).to eq(veteran_b_icn)
          expect(JSON.parse(draft_b.form_data)['veteranInformation']['firstName']).to eq('ClaimantB')
        end
      end
    end

    describe 'DELETE destroy' do
      context 'when the form does not exist' do
        it 'returns 404' do
          delete "#{base_path}?claimant_id=#{claimant_id}"
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when the form exists for this rep and veteran' do
        let!(:form) do
          create(:representative_in_progress_form,
                 rep_user_account: rep_user.user_account,
                 veteran_icn:,
                 form_id:)
        end

        it 'deletes the form and returns 204' do
          expect do
            delete "#{base_path}?claimant_id=#{claimant_id}"
          end.to change(AccreditedRepresentativePortal::RepresentativeInProgressForm, :count).by(-1)

          expect(response).to have_http_status(:no_content)
        end
      end

      context 'when the form belongs to a different rep' do
        before do
          create(:representative_in_progress_form,
                 rep_user_account: create(:user_account),
                 veteran_icn:,
                 form_id:)
        end

        it 'returns 404' do
          delete "#{base_path}?claimant_id=#{claimant_id}"
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end
