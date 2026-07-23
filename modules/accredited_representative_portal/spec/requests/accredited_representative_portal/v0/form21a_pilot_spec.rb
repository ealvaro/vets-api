# frozen_string_literal: true

require_relative '../../../rails_helper'

RSpec.describe 'AccreditedRepresentativePortal::V0 Form 21a pilot gate', type: :request do
  let(:representative_user) { create(:representative_user) }
  let(:headers) { { 'Content-Type' => 'application/json' } }
  let(:pilot_flag) { :accredited_representative_portal_form_21a_pilot }
  let(:feature_flag) { :accredited_representative_portal_form_21a }

  before { login_as(representative_user) }

  def stub_monthly_limit(limit)
    stub_const('AccreditedRepresentativePortal::Form21aPilotGate::MONTHLY_LIMIT', limit)
  end

  describe 'GET /accredited_representative_portal/v0/form21a/pilot_status' do
    it 'returns the read-only pilot status without consuming a slot' do
      expect do
        get('/accredited_representative_portal/v0/form21a/pilot_status')
      end.not_to change(AccreditedRepresentativePortal::Form21aPilotAdmission, :count)

      expect(response).to have_http_status(:ok)
      expect(parsed_response).to eq(
        'state' => 'open',
        'admissions_this_month' => 0,
        'monthly_limit' => 50,
        'remaining' => 50
      )
    end

    it 'reports closed when the monthly cap is reached' do
      stub_monthly_limit(1)
      create(:form21a_pilot_admission)

      get('/accredited_representative_portal/v0/form21a/pilot_status')

      expect(response).to have_http_status(:ok)
      expect(parsed_response).to include('state' => 'closed', 'remaining' => 0)
    end

    it 'returns 404 when the pilot flag is off' do
      allow(Flipper).to receive(:enabled?).with(pilot_flag, anything).and_return(false)

      get('/accredited_representative_portal/v0/form21a/pilot_status')

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the feature flag is off' do
      allow(Flipper).to receive(:enabled?).with(feature_flag).and_return(false)

      get('/accredited_representative_portal/v0/form21a/pilot_status')

      expect(response).to have_http_status(:not_found)
    end

    context 'when the user is not LOA3' do
      let(:non_loa3_user) { create(:representative_user) }

      before do
        allow_any_instance_of(AccreditedRepresentativePortal::V0::Form21aController)
          .to receive(:current_user)
          .and_return(non_loa3_user)
        allow(non_loa3_user).to receive(:loa).and_return({ current: 1, highest: 1 })
        login_as(non_loa3_user)
      end

      it 'returns 404' do
        get('/accredited_representative_portal/v0/form21a/pilot_status')
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /accredited_representative_portal/v0/in_progress_forms/21a (new draft)' do
    let(:body) { { formData: { field: 'value' } }.to_json }

    def put_new_draft
      put('/accredited_representative_portal/v0/in_progress_forms/21a', params: body, headers:)
    end

    it 'consumes a pilot slot and saves the draft when the pilot is open' do
      expect { put_new_draft }
        .to change(AccreditedRepresentativePortal::Form21aPilotAdmission, :count).by(1)
        .and change(InProgressForm, :count).by(1)

      expect(response).to have_http_status(:ok)
      admission = AccreditedRepresentativePortal::Form21aPilotAdmission.last
      expect(admission.user_account_id).to eq(representative_user.user_account.id)
      expect(admission.status).to eq('started')
    end

    it 'returns 403 and rolls back without creating a draft when the pilot is closed' do
      stub_monthly_limit(1)
      create(:form21a_pilot_admission)

      expect { put_new_draft }
        .to not_change(AccreditedRepresentativePortal::Form21aPilotAdmission, :count)
        .and not_change(InProgressForm, :count)

      expect(response).to have_http_status(:forbidden)
      expect(parsed_response['errors']).to be_present
    end

    it 'does not consume a slot for an already-admitted user' do
      create(:form21a_pilot_admission, user_account: representative_user.user_account)

      expect { put_new_draft }
        .to not_change(AccreditedRepresentativePortal::Form21aPilotAdmission, :count)
        .and change(InProgressForm, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it 'skips the gate entirely when the pilot flag is off' do
      allow(Flipper).to receive(:enabled?).with(pilot_flag, anything).and_return(false)

      expect { put_new_draft }
        .to not_change(AccreditedRepresentativePortal::Form21aPilotAdmission, :count)
        .and change(InProgressForm, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it 'does not re-run the gate when updating an existing draft' do
      create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid)

      expect { put_new_draft }
        .not_to change(AccreditedRepresentativePortal::Form21aPilotAdmission, :count)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accredited_representative_portal/v0/form21a (submission)' do
    let(:form_data) do
      {
        'firstName' => 'John',
        'lastName' => 'Doe',
        'icnNo' => representative_user.icn,
        'uId' => representative_user.uuid
      }
    end
    let(:payload) { { form21aSubmission: { form: form_data.to_json } }.to_json }
    let(:mock_schema) do
      {
        '$schema' => 'http://json-schema.org/draft-04/schema#',
        'type' => 'object',
        'properties' => { 'firstName' => { 'type' => 'string' } },
        'required' => ['firstName'],
        'additionalProperties' => true
      }
    end

    before do
      stub_const('VetsJsonSchema::SCHEMAS', VetsJsonSchema::SCHEMAS.merge('21A' => mock_schema))
      create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid)
      allow(AccreditationService).to receive(:submit_form21a).and_return(
        instance_double(
          Faraday::Response,
          success?: true,
          body: { 'uploaded' => [{ 'application' => { 'id' => '12345' } }], 'result' => 'success' },
          status: 201
        )
      )
    end

    it 'transitions the pilot admission to submitted on a successful submission' do
      admission = create(:form21a_pilot_admission, user_account: representative_user.user_account)

      post('/accredited_representative_portal/v0/form21a', params: payload, headers:)

      expect(response).to have_http_status(:created)
      admission.reload
      expect(admission.status).to eq('submitted')
      expect(admission.submitted_at).to be_present
    end

    it 'succeeds without error when the user has no pilot admission' do
      expect do
        post('/accredited_representative_portal/v0/form21a', params: payload, headers:)
      end.not_to change(AccreditedRepresentativePortal::Form21aPilotAdmission, :count)

      expect(response).to have_http_status(:created)
    end

    it 'preserves the original submitted_at when an already-submitted admission is resubmitted' do
      original_time = 3.days.ago
      admission = create(
        :form21a_pilot_admission, :submitted,
        user_account: representative_user.user_account, submitted_at: original_time
      )

      post('/accredited_representative_portal/v0/form21a', params: payload, headers:)

      expect(response).to have_http_status(:created)
      admission.reload
      expect(admission.status).to eq('submitted')
      expect(admission.submitted_at).to be_within(1.second).of(original_time)
    end
  end
end
