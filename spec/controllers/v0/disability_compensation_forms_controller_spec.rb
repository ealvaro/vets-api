# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::DisabilityCompensationFormsController, type: :controller do
  let(:user) { build(:user, :loa3, :legacy_icn) }
  let(:user_without_icn) { build(:user, :loa3, icn: '') }
  let(:user_without_ssn) { build(:user, :loa3, ssn: '') }
  let(:user_without_edipi) { build(:user, :loa3, edipi: '') }
  let(:user_without_participant_id) { build(:user, :loa3, participant_id: '') }

  before do
    sign_in_as(user)
  end

  describe '#separation_locations' do
    context 'lighthouse' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('production')
      end

      it 'returns separation locations' do
        VCR.use_cassette('brd/separation_locations') do
          get(:separation_locations)
          expect(JSON.parse(response.body)['separation_locations'].present?).to be(true)
        end
      end

      it 'uses the cached response on the second request' do
        VCR.use_cassette('brd/separation_locations') do
          2.times do
            get(:separation_locations)
            expect(response).to have_http_status(:ok)
          end
        end
      end
    end

    context 'lighthouse staging' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('staging')
      end

      it 'returns separation locations' do
        VCR.use_cassette('brd/separation_locations_staging') do
          get(:separation_locations)
          expect(JSON.parse(response.body)['separation_locations'].present?).to be(true)
        end
      end

      it 'uses the cached response on the second request' do
        VCR.use_cassette('brd/separation_locations_staging') do
          2.times do
            get(:separation_locations)
            expect(response).to have_http_status(:ok)
          end
        end
      end
    end
  end

  describe '#rated_disabilities' do
    let(:retry_toggle) { :disability_compensation_retry_lh_rating_requests }
    let(:invoker) { 'V0::DisabilityCompensationFormsController#rated_disabilities' }
    let(:api_provider) { instance_double(LighthouseRatedDisabilitiesProvider) }
    let(:rated_disabilities_response) { build(:rated_disabilities_response) }

    before do
      allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')
    end

    context 'when the retry toggle is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(retry_toggle, instance_of(User)).and_return(false)
      end

      it 'calls get_rated_disabilities directly and returns a successful response' do
        VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
          get(:rated_disabilities)
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context 'when the retry toggle is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(retry_toggle, instance_of(User)).and_return(true)
        allow(ApiProviderFactory).to receive(:call).and_return(api_provider)
        allow(Kernel).to receive(:sleep) # prevent real backoff delays in retry tests
      end

      context 'when the circuit is closed (no outage)' do
        before do
          allow(VeteranVerification::Configuration.instance).to receive(:breakers_service)
            .and_return(instance_double(Breakers::Service, latest_outage: nil))
          allow(api_provider).to receive(:get_rated_disabilities).and_return(rated_disabilities_response)
        end

        it 'calls get_rated_disabilities inside with_retries and returns a successful response' do
          get(:rated_disabilities)
          expect(response).to have_http_status(:ok)
          expect(api_provider).to have_received(:get_rated_disabilities).once
        end
      end

      context 'when the circuit is open (Breakers outage)' do
        let(:lh_outage_service) { instance_double(Breakers::Service, name: 'VeteranVerification') }
        let(:lh_outage) { instance_double(Breakers::Outage, ended?: false, service: lh_outage_service, start_time: Time.zone.now) }
        let(:lh_breakers_service) { instance_double(Breakers::Service, latest_outage: lh_outage) }

        before do
          allow(VeteranVerification::Configuration.instance).to receive(:breakers_service)
            .and_return(lh_breakers_service)
        end

        it 'logs a warning about the service outage' do
          allow(Rails.logger).to receive(:warn)
          expect(Rails.logger).to receive(:warn).with(
            'Skipping get_rated_disabilities due to service outage',
            { invoker: }
          )
          get(:rated_disabilities)
        end

        it 'does not call the API provider and returns service unavailable' do
          allow(Rails.logger).to receive(:warn)
          expect(api_provider).not_to receive(:get_rated_disabilities)
          get(:rated_disabilities)
          expect(response).to have_http_status(:service_unavailable)
        end
      end
    end
  end

  describe '#rating_info' do
    context 'retrieve from Lighthouse' do
      before do
        allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')

        allow(Flipper).to receive(:enabled?).with(:profile_lighthouse_rating_info, instance_of(User))
                                            .and_return(true)
      end

      it 'returns disability rating' do
        VCR.use_cassette('lighthouse/veteran_verification/disability_rating/200_response') do
          get(:rating_info)
          expect(response).to have_http_status(:ok)

          data = JSON.parse(response.body)['data']['attributes']
          expect(data['user_percent_of_disability']).to eq(100)
          expect(data['source_system']).to eq('Lighthouse')
        end
      end

      context 'user missing icn' do
        before do
          sign_in_as(user_without_icn)
        end

        it 'responds with forbidden' do
          get(:rating_info)
          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when Lighthouse returns a 500' do
        before do
          allow_any_instance_of(LighthouseRatedDisabilitiesProvider).to receive(:get_combined_disability_rating)
            .and_raise(Common::Exceptions::ExternalServerInternalServerError)
        end

        it 'responds with bad_gateway (502)' do
          allow_any_instance_of(DisabilityCompensation::Loggers::Monitor).to receive(:track_request)
          get(:rating_info)
          expect(response).to have_http_status(:bad_gateway)
        end

        it 'logs the upstream error via monitor' do
          expect_any_instance_of(DisabilityCompensation::Loggers::Monitor)
            .to receive(:track_request).with(:warn, 'rating_info upstream error',
                                             'api.disability_compensation.rating_info.upstream_error', anything)
          get(:rating_info)
        end
      end
    end

    context 'retrieve from EVSS' do
      before do
        allow(Flipper).to receive(:enabled?).with(:profile_lighthouse_rating_info, instance_of(User))
                                            .and_return(false)
      end

      it 'returns disability rating' do
        VCR.use_cassette('evss/disability_compensation_form/rating_info') do
          get(:rating_info)
          expect(response).to have_http_status(:ok)

          data = JSON.parse(response.body)['data']['attributes']
          expect(data['user_percent_of_disability']).to eq(100)
          expect(data['source_system']).to eq('EVSS')
        end
      end

      context 'user is missing snn, edipi, or participant id' do
        it 'responds with forbidden' do
          [user_without_ssn, user_without_edipi, user_without_participant_id].each do |user|
            sign_in_as(user)
            get(:rating_info)
            expect(response).to have_http_status(:forbidden)
          end
        end
      end
    end
  end

  describe '#submit_all_claim' do
    let(:saved_claim) { build(:va526ez) }

    before do
      allow(SavedClaim::DisabilityCompensation::Form526AllClaim).to(
        receive(:from_hash).and_return(saved_claim)
      )
    end

    it 'populates form_start_date on the SavedClaim from the InProgressForm.created_at' do
      in_progress_form = create(:in_progress_526_form, user_uuid: user.uuid, created_at: 3.days.ago)

      post(:submit_all_claim, body: '{}', as: :json)
      expect(saved_claim.form_start_date).to eq(in_progress_form.created_at)
    end

    it 'leaves form_start_date nil when no InProgressForm exists for the user' do
      post(:submit_all_claim, body: '{}', as: :json)
      expect(saved_claim.form_start_date).to be_nil
    end
  end
end
