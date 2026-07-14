# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/benefits_claims/service'

RSpec.describe 'V0::IntentsToFile', type: :request do
  let(:user) { build(:disabilities_compensation_user, icn: '123498767V234859') }

  before do
    sign_in_as(user)
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('test_token')
  end

  describe 'GET /v0/intents_to_file' do
    context 'when all three ITF types have active records' do
      it 'returns ITFs for all types' do
        VCR.use_cassettes([
                            { name: 'lighthouse/benefits_claims/intent_to_file/200_response' },
                            { name: 'lighthouse/benefits_claims/intent_to_file/200_response_pension' },
                            { name: 'lighthouse/benefits_claims/intent_to_file/200_response_survivor' }
                          ]) do
          get '/v0/intents_to_file'

          expect(response).to have_http_status(:ok)
          body = JSON.parse(response.body)
          expect(body['data'].length).to eq(3)

          types = body['data'].map { |itf| itf['type'] }
          expect(types).to contain_exactly('compensation', 'pension', 'survivor')
        end
      end

      it 'records Datadog metrics for types and statuses' do
        VCR.use_cassettes([
                            { name: 'lighthouse/benefits_claims/intent_to_file/200_response' },
                            { name: 'lighthouse/benefits_claims/intent_to_file/200_response_pension' },
                            { name: 'lighthouse/benefits_claims/intent_to_file/200_response_survivor' }
                          ]) do
          allow(StatsD).to receive(:increment)

          get '/v0/intents_to_file'

          expect(StatsD).to have_received(:increment).with(
            'api.intents_to_file.fetch',
            tags: array_including('type:compensation', 'status:active')
          )
          expect(StatsD).to have_received(:increment).with(
            'api.intents_to_file.fetch',
            tags: array_including('type:pension', 'status:active')
          )
          expect(StatsD).to have_received(:increment).with(
            'api.intents_to_file.fetch',
            tags: array_including('type:survivor', 'status:active')
          )
        end
      end

      context 'when some ITF types return 404 (no active ITF)' do
        it 'returns only the ITFs that exist' do
          VCR.use_cassettes([
                              { name: 'lighthouse/benefits_claims/intent_to_file/200_response' },
                              { name: 'lighthouse/benefits_claims/intent_to_file/404_response_pension' },
                              { name: 'lighthouse/benefits_claims/intent_to_file/404_response_survivor' }
                            ]) do
            get '/v0/intents_to_file'

            expect(response).to have_http_status(:ok)
            body = JSON.parse(response.body)
            expect(body['data'].length).to eq(1)
            expect(body['data'][0]['type']).to eq('compensation')
          end
        end
      end

      context 'when all ITF types return 404' do
        it 'returns an empty array' do
          VCR.use_cassettes([
                              { name: 'lighthouse/benefits_claims/intent_to_file/404_response' },
                              { name: 'lighthouse/benefits_claims/intent_to_file/404_response_pension' },
                              { name: 'lighthouse/benefits_claims/intent_to_file/404_response_survivor' }
                            ]) do
            get '/v0/intents_to_file'

            expect(response).to have_http_status(:ok)
            body = JSON.parse(response.body)
            expect(body['data']).to eq([])
          end
        end
      end

      context 'when Lighthouse returns a server error' do
        it 'logs and raises the error' do
          allow_any_instance_of(BenefitsClaims::Service).to receive(:get_intent_to_file)
            .and_raise(Common::Exceptions::ExternalServerInternalServerError.new)
          allow(Rails.logger).to receive(:error)

          get '/v0/intents_to_file'

          expect(response).to have_http_status(:internal_server_error)
          expect(Rails.logger).to have_received(:error).with(
            'IntentsToFileController error fetching ITFs',
            hash_including(
              error_class: 'Common::Exceptions::ExternalServerInternalServerError',
              error_message: 'Internal server error'
            )
          )
        end

        it 'increments the error metric' do
          allow_any_instance_of(BenefitsClaims::Service).to receive(:get_intent_to_file)
            .and_raise(Common::Exceptions::ExternalServerInternalServerError.new)
          allow(StatsD).to receive(:increment)

          get '/v0/intents_to_file'

          expect(StatsD).to have_received(:increment).with(
            'api.intents_to_file.error',
            tags: array_including('service:intents-to-file')
          )
        end
      end
    end
  end
end
