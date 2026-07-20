# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'VRE::V0::Ch31CaseDetails', type: :request do
  include SchemaMatchers

  before { sign_in_as(user) }

  describe 'GET vre/v0/ch31_case_details' do
    context 'when case details available' do
      let(:user) { create(:user, icn: '1012662125V786396') }

      it 'returns 200 response' do
        VCR.use_cassette('vre/ch31_case_details/200') do
          get '/vre/v0/ch31_case_details'
          expect(response).to match_response_schema('vre/ch31_case_details')
          attributes = JSON.parse(response.body).dig('data', 'attributes')
          expect(attributes['is_initial_evaluation_step_code_of_conduct_completed']).to be(true)
          expect(attributes['has_veteran_opted_for_eva']).to be(true)
          assert_response :success
        end
      end
    end

    context 'when no icn present' do
      let(:user) { create(:user, icn: nil) }

      it 'raises ParameterMissing error' do
        get '/vre/v0/ch31_case_details'
        expect(response).to have_http_status(:bad_request)
        message = JSON.parse(response.body)['errors'].first['detail']
        expect(message).to eq('The required parameter "ICN", is missing')
      end
    end

    context 'when case details forbidden for user' do
      let(:user) { create(:user, icn: '1234') }

      it 'returns 403 response' do
        VCR.use_cassette('vre/ch31_case_details/403') do
          get '/vre/v0/ch31_case_details'
          expect(response).to have_http_status(:forbidden)
          message = JSON.parse(response.body)['errors'].first['detail']
          expect(message).to eq('Forbidden')
        end
      end
    end

    context 'when RES has no application associated with the ICN' do
      let(:user) { create(:user, icn: '9999999999V999999') }

      it 'returns 403 with NO_APP_IN_RES error details' do
        VCR.use_cassette('vre/ch31_case_details/403_no_app_in_res') do
          get '/vre/v0/ch31_case_details'
          expect(response).to have_http_status(:forbidden)
          error = JSON.parse(response.body)['errors'].first
          expect(error['code']).to eq('NO_APP_IN_RES')
          expect(error['title']).to eq('No App in RES for ICN')
          expect(error['detail']).to eq('RES does not have an application associated with this ICN.')
        end
      end
    end

    context 'when upstream service is not available' do
      let(:user) { create(:user, icn: '1012667145V762142') }

      it 'returns 503 response' do
        VCR.use_cassette('vre/ch31_case_details/500') do
          get '/vre/v0/ch31_case_details'
          expect(response).to have_http_status(:service_unavailable)
          message = JSON.parse(response.body)['errors'].first['detail']
          expect(message).to eq('Service Unavailable')
        end
      end
    end
  end
end
