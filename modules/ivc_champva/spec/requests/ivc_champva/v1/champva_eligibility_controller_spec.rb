# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'IvcChampva::V1::ChampvaEligibilityController', type: :request do
  let(:transaction_uuid) { SecureRandom.uuid }
  let(:form_uuid) { SecureRandom.uuid }
  let(:duplicate_form_uuid) { SecureRandom.uuid }
  let(:service_result) do
    {
      status: 'success',
      persons: [
        { icn: '0000001200603250V008079000000', person_uuid: '682', person_type: 'SPONSOR' },
        { icn: '0000001200603251V181504000000', person_uuid: '638', person_type: 'BENEFICIARY' }
      ],
      created_count: 0,
      existing_count: 2,
      names_updated_count: 0,
      eligibility_updated_count: 2,
      cached: true
    }
  end
  let(:eligibility_results) do
    [
      {
        transaction_uuid:,
        form_uuids: [form_uuid],
        **service_result
      }
    ]
  end

  before do
    allow_any_instance_of(IvcChampva::V1::ChampvaEligibilityController)
      .to receive(:authenticate).and_return(true)
    allow(Flipper).to receive(:enabled?).and_return(false)
    allow(Flipper).to receive(:enabled?)
      .with(:ivc_champva_ves_eligibility_on_demand, anything)
      .and_return(feature_enabled)

    allow_any_instance_of(IvcChampva::V1::ChampvaEligibilityController)
      .to receive(:eligibility_results).and_return(eligibility_results)
  end

  describe 'POST /ivc_champva/v1/forms/champva_eligibility' do
    subject(:make_request) do
      post '/ivc_champva/v1/forms/champva_eligibility',
           params: request_body.to_json,
           headers: { 'Content-Type' => 'application/json' }
    end

    let(:feature_enabled) { true }
    let(:request_body) { { form_uuids: [form_uuid] } }
    let!(:form) { create(:ivc_champva_form, form_uuid:, transaction_uuid:) }

    context 'when the feature flag is disabled' do
      let(:feature_enabled) { false }

      it 'returns not found' do
        make_request

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error_message']).to eq('Not found')
      end
    end

    context 'when form_uuids is missing' do
      let(:request_body) { {} }

      it 'returns unprocessable entity' do
        make_request

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error_message']).to eq('form_uuids must be a non-empty array')
      end
    end

    context 'when form_uuids is an empty array' do
      let(:request_body) { { form_uuids: [] } }

      it 'returns unprocessable entity' do
        make_request

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error_message']).to eq('form_uuids must be a non-empty array')
      end
    end

    context 'with a valid request' do
      it 'returns results from the service and stamps last_ves_fetch_at' do
        make_request

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)

        expect(body.dig('data', 'form_uuids')).to contain_exactly(form_uuid)
        result = body.dig('data', 'results', 0)
        expect(result['status']).to eq('success')
        expect(result['created_count']).to eq(0)
        expect(result['eligibility_updated_count']).to eq(2)
        expect(form.reload.last_ves_fetch_at).to be_present
      end
    end

    context 'when the application is rate limited' do
      before do
        form.update!(last_ves_fetch_at: 5.minutes.ago)
      end

      it 'returns 429 and retry-after header' do
        make_request

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers['Retry-After']).to be_present
        expect(response.parsed_body['error_message']).to eq('Rate limit exceeded. Please try again later.')
      end
    end

    context 'when eligibility processing raises an unexpected error' do
      before do
        allow_any_instance_of(IvcChampva::V1::ChampvaEligibilityController)
          .to receive(:eligibility_results).and_raise(StandardError, 'boom')
      end

      it 'returns 500 and still stamps last_ves_fetch_at before the failure' do
        make_request

        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body['error_message']).to eq('Error: boom')
        expect(form.reload.last_ves_fetch_at).to be_present
      end
    end
  end
end
