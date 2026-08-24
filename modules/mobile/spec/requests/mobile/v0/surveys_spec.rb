# frozen_string_literal: true

require_relative '../../../support/helpers/rails_helper'
require_relative '../../../support/helpers/committee_helper'

RSpec.describe 'Mobile::V0::Surveys', type: :request do
  include CommitteeHelper
  let!(:user) { sis_user(:mhv) }

  describe 'POST /mobile/v0/survey' do
    let(:survey_data) do
      {
        'q01' => {
          'type' => 'free_response',
          'label' => 'Explain your issue',
          'value' => 'This is my response'
        },
        'q02' => {
          'type' => 'multiple_choice',
          'label' => 'Rate from 1-5',
          'value' => '4',
          'color' => 'purple'
        }
      }
    end

    let(:metadata) do
      {
        'os' => 'iOS',
        'version' => '15.0'
      }
    end

    let(:valid_params) do
      {
        'surveyType' => 'giveFeedback',
        'surveyData' => survey_data,
        'metadata' => metadata
      }
    end

    context 'with valid parameters' do
      it 'creates a survey response and returns 204' do
        expect do
          post '/mobile/v0/survey', params: valid_params, headers: sis_headers, as: :json
        end.to change(Mobile::SurveyResponse, :count).by(1)

        assert_schema_conform(204)

        survey_response = Mobile::SurveyResponse.last
        expect(survey_response.survey_type).to eq('giveFeedback')
        expect(survey_response.user_uuid).to eq(user.uuid)
        expect(survey_response.survey_data).to eq(survey_data)
        expect(survey_response.metadata).to eq(metadata)
      end

      it 'normalizes nested survey_data keys from camelCase to snake_case on persistence' do
        params = valid_params.deep_dup
        params['surveyData']['q01']['altValue'] = '4'

        post '/mobile/v0/survey', params:, headers: sis_headers, as: :json

        expect(response).to have_http_status(:no_content)

        survey_response = Mobile::SurveyResponse.last
        q01 = survey_response.survey_data['q01']

        expect(q01).to include('alt_value' => '4')
        expect(q01).not_to have_key('altValue')
      end

      it 'allows for empty metadata' do
        params = valid_params.dup
        params['metadata'] = {}

        expect do
          post '/mobile/v0/survey', params:, headers: sis_headers, as: :json
        end.to change(Mobile::SurveyResponse, :count).by(1)

        assert_schema_conform(204)

        survey_response = Mobile::SurveyResponse.last
        expect(survey_response.metadata).to eq({})
      end
    end

    context 'with invalid parameters' do
      it 'returns 422 when surveyType is missing' do
        params = valid_params.dup
        params.delete('surveyType')

        post '/mobile/v0/survey', params:, headers: sis_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)['errors']
        expect(errors.map { |e| e['detail'] }).to include('survey-type - can\'t be blank')
      end

      it 'returns 422 when surveyData is missing' do
        params = valid_params.dup
        params.delete('surveyData')

        post '/mobile/v0/survey', params:, headers: sis_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)['errors']
        expect(errors.map { |e| e['detail'] }).to include('survey-data - can\'t be blank')
      end

      it 'returns 422 when survey_data has invalid structure' do
        params = valid_params.dup
        params[:surveyData] = {
          'q01' => {
            'type' => 'free_response',
            'label' => 'Explain your issue'
            # missing 'value'
          }
        }

        post '/mobile/v0/survey', params:, headers: sis_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)['errors']
        expect(errors.map { |e| e['detail'] }).to include('survey-data - question q01 missing required fields: value')
      end

      it 'returns 422 when survey_type is invalid' do
        params = valid_params.dup
        params[:surveyType] = 'invalid_survey'

        post '/mobile/v0/survey', params:, headers: sis_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)['errors']
        expect(errors.map { |e| e['detail'] }).to include('survey-type - is not included in the list')
      end
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        post '/mobile/v0/survey', params: valid_params

        assert_schema_conform(401)
      end
    end
  end
end
