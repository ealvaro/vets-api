# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::RatedDisabilitiesController, type: :controller do
  let(:user) { create(:user, :loa3, :accountable, :legacy_icn) }

  before do
    sign_in_as(user)

    token = 'blahblech'

    allow_any_instance_of(VeteranVerification::Configuration).to receive(:access_token).and_return(token)
  end

  describe '#show' do
    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('lighthouse/veteran_verification/show/200_response') do
          get(:show)
        end

        expect(response).to have_http_status(:ok)
      end

      it 'only returns active ratings', run_at: '2025-02-01T18:48:27Z' do
        VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_inactives_response') do
          get(:show)
        end

        expect(response).to have_http_status(:ok)

        # VCR Cassette should have 5 items in the individual_ratings array, only 4 should
        # be "active" (1 of which should have a `rating_end_date` in the future)
        parsed_body = JSON.parse(response.body)
        expect(parsed_body.dig('data', 'attributes', 'individual_ratings').length).to eq(4)
      end

      it 'removes the Veterans ICN from the response before sending' do
        VCR.use_cassette('lighthouse/veteran_verification/show/200_response') do
          get(:show)
        end

        expect(response).to have_http_status(:ok)

        parsed_body = JSON.parse(response.body)
        expect(parsed_body.dig('data', 'id')).to eq('')
      end

      context 'when suppress_nsc_rating_percentage_web is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:suppress_nsc_rating_percentage_web,
                                                    instance_of(User)).and_return(true)
        end

        it 'preserves rating_percentage for service-connected disabilities' do
          VCR.use_cassette('lighthouse/veteran_verification/show/200_response') do
            get(:show)
          end

          parsed_body = JSON.parse(response.body)
          sc = parsed_body.dig('data', 'attributes', 'individual_ratings')
                          .find { |r| r['decision'] == 'Service Connected' }
          expect(sc['rating_percentage']).to eq(50)
        end

        it 'suppresses rating_percentage for non-service-connected disabilities' do
          VCR.use_cassette('lighthouse/veteran_verification/show/200_response') do
            get(:show)
          end

          parsed_body = JSON.parse(response.body)
          nsc = parsed_body.dig('data', 'attributes', 'individual_ratings')
                           .find { |r| r['decision'] == 'Not Service Connected' }
          expect(nsc['rating_percentage']).to be_nil
        end
      end

      context 'when suppress_nsc_rating_percentage_web is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:suppress_nsc_rating_percentage_web,
                                                    instance_of(User)).and_return(false)
        end

        it 'returns rating_percentage for non-service-connected disabilities' do
          VCR.use_cassette('lighthouse/veteran_verification/show/200_response') do
            get(:show)
          end

          parsed_body = JSON.parse(response.body)
          nsc = parsed_body.dig('data', 'attributes', 'individual_ratings')
                           .find { |r| r['decision'] == 'Not Service Connected' }
          expect(nsc['rating_percentage']).not_to be_nil
        end
      end
    end

    context 'when not authorized' do
      it 'returns a status of 401' do
        VCR.use_cassette('lighthouse/veteran_verification/disability_rating/401_response') do
          get(:show)
        end

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when ICN not found' do
      it 'returns a status of 404' do
        VCR.use_cassette('lighthouse/veteran_verification/disability_rating/404_ICN_response') do
          get(:show)
        end

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when there is a gateway timeout' do
      it 'returns a status of 504' do
        VCR.use_cassette('lighthouse/veteran_verification/disability_rating/504_response') do
          get(:show)
        end

        expect(response).to have_http_status(:gateway_timeout)
      end
    end

    context 'when the Lighthouse circuit breaker is open' do
      before do
        mock_service = instance_double(Breakers::Service, name: 'VeteranVerification')
        mock_outage = instance_double(Breakers::Outage, start_time: Time.zone.now, service: mock_service)
        error = Breakers::OutageException.new(mock_outage, mock_service)
        allow_any_instance_of(VeteranVerification::Service).to receive(:get_rated_disabilities).and_raise(error)
      end

      it 'returns a status of 503 instead of a 500' do
        get(:show)

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when Lighthouse returns a non-JSON body' do
      before do
        allow_any_instance_of(VeteranVerification::Service)
          .to receive(:get_rated_disabilities).and_raise(Common::Exceptions::BadGateway)
      end

      it 'returns a status of 502 instead of a 500' do
        get(:show)

        expect(response).to have_http_status(:bad_gateway)
      end
    end

    context 'when an unexpected error occurs' do
      let(:error) { StandardError.new('Unexpected service error') }

      before do
        allow_any_instance_of(VeteranVerification::Service).to receive(:get_rated_disabilities).and_raise(error)
        allow(Rails.logger).to receive(:error).and_call_original
      end

      it 'logs the error with detailed context before re-raising' do
        expect(Rails.logger).to receive(:error).with(
          'RatedDisabilitiesController error',
          hash_including(
            error_class: 'StandardError',
            error_message: 'Unexpected service error',
            user_uuid: user.uuid
          )
        ).and_call_original

        get(:show)

        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end
end
