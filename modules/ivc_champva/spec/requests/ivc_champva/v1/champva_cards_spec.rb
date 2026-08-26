# frozen_string_literal: true

require 'rails_helper'
require 'ves_api/client'

RSpec.describe 'IvcChampva::V1::ChampvaCardsController', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :loa3, first_name: 'Alex', last_name: 'Doe') }
  let(:feature_enabled) { true }
  let(:ves_client) { instance_double(IvcChampva::VesApi::Client) }
  # Sanitized VES ChampvaDigitalCardData response fixture (shape mirrors SQA; IDs redacted).
  # Real payload shape includes relationshipType, sponsor, studentChildAttendanceDetails, etc.
  # Eligibility window is 2002-02-22 -> 2024-06-01, so tests use travel_to to land inside/outside it.
  let(:card_dataset_response) do
    JSON.parse(
      File.read('modules/ivc_champva/spec/fixtures/ves/champva_digital_card_data.json')
    )['data']
  end
  let(:covering_ee_summary) do
    {
      'vfmpProgramsInfo' => {
        'relationships' => [
          {
            'champvaEligibilities' => [
              {
                'eligibilityDates' => [
                  { 'startDate' => '2011-01-01', 'endDate' => '2099-01-31' }
                ]
              }
            ]
          }
        ]
      }
    }
  end

  def make_request
    get '/ivc_champva/v1/champva_card'
  end

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:champva_benefits_card, anything).and_return(feature_enabled)
    allow(IvcChampva::VesApi::Client).to receive(:new).and_return(ves_client)
    allow(ves_client).to receive(:get_ee_summary).and_return(covering_ee_summary)
  end

  describe 'GET /ivc_champva/v1/champva_card' do
    context 'when not logged in' do
      it 'returns unauthorized' do
        make_request

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when logged in' do
      before { sign_in_as(user) }

      context 'when the feature flag is disabled' do
        let(:feature_enabled) { false }

        it 'returns not found' do
          make_request

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body['error_message']).to eq('Not found')
        end
      end

      context 'when the user has no ICN' do
        before { allow_any_instance_of(User).to receive(:icn).and_return(nil) }

        it 'returns unprocessable content' do
          make_request

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body.dig('error', 'code')).to eq('missing_icn')
        end
      end

      context 'when the user is currently enrolled' do
        # Uses the real ChampvaDigitalCardData payload; travel inside its eligibility window.
        let(:covering_ee_summary) { card_dataset_response }

        it 'returns card attributes' do
          travel_to(Date.new(2023, 1, 1)) do
            make_request

            expect(response).to have_http_status(:ok)
            expect(response.parsed_body).to eq(
              'data' => {
                'type' => 'champva_card',
                'attributes' => {
                  'full_name' => 'Alex Doe',
                  'effective_date' => '02/2002',
                  'expiration_date' => '06/2024'
                }
              }
            )
          end
        end
      end

      context 'when VES has no CHAMPVA record' do
        before { allow(ves_client).to receive(:get_ee_summary).and_return({}) }

        it 'returns not enrolled' do
          make_request

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body.dig('error', 'code')).to eq('not_enrolled')
        end
      end

      context 'when eligibility is expired' do
        # Real ChampvaDigitalCardData payload, evaluated after its window closed (2024-06-01).
        let(:covering_ee_summary) { card_dataset_response }

        it 'returns not enrolled' do
          travel_to(Date.new(2025, 1, 1)) do
            make_request

            expect(response).to have_http_status(:not_found)
            expect(response.parsed_body.dig('error', 'code')).to eq('not_enrolled')
          end
        end
      end

      context 'when eligibility starts in the future' do
        let(:covering_ee_summary) do
          {
            'vfmpProgramsInfo' => {
              'relationships' => [
                {
                  'champvaEligibilities' => [
                    {
                      'eligibilityDates' => [
                        { 'startDate' => '2099-01-01', 'endDate' => '2100-01-31' }
                      ]
                    }
                  ]
                }
              ]
            }
          }
        end

        it 'returns not enrolled' do
          make_request

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body.dig('error', 'code')).to eq('not_enrolled')
        end
      end

      context 'when VES times out' do
        before do
          allow(ves_client).to receive(:get_ee_summary)
            .and_raise(IvcChampva::VesApi::VesApiTimeoutError, 'timeout')
        end

        it 'returns gateway timeout' do
          make_request

          expect(response).to have_http_status(:gateway_timeout)
          expect(response.parsed_body.dig('error', 'code')).to eq('upstream_timeout')
        end
      end

      context 'when VES returns an upstream error' do
        before do
          allow(ves_client).to receive(:get_ee_summary)
            .and_raise(IvcChampva::VesApi::VesApiError, 'response code: 500')
        end

        it 'returns bad gateway' do
          make_request

          expect(response).to have_http_status(:bad_gateway)
          expect(response.parsed_body.dig('error', 'code')).to eq('upstream_error')
        end
      end
    end
  end
end
