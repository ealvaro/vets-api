# frozen_string_literal: true

require 'rails_helper'
require 'disability_compensation/factories/api_provider_factory'

RSpec.describe RatedDisabilitiesFetchConcern do
  let(:user) { build(:evss_user, icn: '123498767V234859') }
  let(:host) do
    Class.new do
      include RetriableConcern
      include RatedDisabilitiesFetchConcern
    end.new
  end

  before do
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('blahblech')
  end

  describe '#rated_disabilities_api_provider' do
    it 'calls ApiProviderFactory with the correct lighthouse type and user options' do
      expect(ApiProviderFactory).to receive(:call).with(
        type: ApiProviderFactory::FACTORIES[:rated_disabilities],
        provider: :lighthouse,
        options: hash_including(icn: user.icn.to_s),
        current_user: user,
        feature_toggle: nil
      )
      host.rated_disabilities_api_provider(user)
    end
  end

  describe '#fetch_rated_disabilities_response' do
    let(:retry_toggle) { :disability_compensation_retry_lh_rating_requests }
    let(:invoker) { 'TestClass#test_method' }
    let(:api_provider) { instance_double(LighthouseRatedDisabilitiesProvider) }
    let(:rated_disabilities_response) { build(:rated_disabilities_response) }

    before do
      allow(api_provider).to receive(:get_rated_disabilities).and_return(rated_disabilities_response)
    end

    context 'when the toggle is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(retry_toggle, user).and_return(false)
      end

      it 'calls get_rated_disabilities directly and returns the response' do
        result = host.fetch_rated_disabilities_response(api_provider, invoker, user)
        expect(result).to eq(rated_disabilities_response)
        expect(api_provider).to have_received(:get_rated_disabilities).with(nil, nil, { invoker: }).once
      end

      it 'does not retry on Common::Exceptions::Timeout' do
        allow(api_provider).to receive(:get_rated_disabilities).and_raise(Common::Exceptions::Timeout)
        expect(Rails.logger).not_to receive(:warn)
        expect { host.fetch_rated_disabilities_response(api_provider, invoker, user) }
          .to raise_error(Common::Exceptions::Timeout)
      end
    end

    context 'when the toggle is not set (defaults to disabled)' do
      it 'calls get_rated_disabilities directly and returns the response' do
        result = host.fetch_rated_disabilities_response(api_provider, invoker, user)
        expect(result).to eq(rated_disabilities_response)
        expect(api_provider).to have_received(:get_rated_disabilities).once
      end
    end

    context 'when the toggle is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(retry_toggle, user).and_return(true)
        allow(VeteranVerification::Configuration.instance).to receive(:breakers_service)
          .and_return(instance_double(Breakers::Service, latest_outage: nil))
        allow(Kernel).to receive(:sleep) # prevent real backoff delays in retry tests
      end

      it 'calls get_rated_disabilities inside with_retries and returns the response' do
        result = host.fetch_rated_disabilities_response(api_provider, invoker, user)
        expect(result).to eq(rated_disabilities_response)
        expect(api_provider).to have_received(:get_rated_disabilities).once
      end

      it 'retries on Common::Exceptions::Timeout and succeeds on the second attempt' do
        attempts = 0
        allow(api_provider).to receive(:get_rated_disabilities) do
          attempts += 1
          raise Common::Exceptions::Timeout if attempts < 2

          rated_disabilities_response
        end

        expect(Rails.logger).to receive(:warn).with(
          "Retrying #{invoker} (Attempt 1/3): Common::Exceptions::Timeout"
        )

        result = host.fetch_rated_disabilities_response(api_provider, invoker, user)
        expect(result).to eq(rated_disabilities_response)
        expect(attempts).to eq(2)
      end

      it 'does not retry on non-transient errors (e.g. ServiceUnavailable)' do
        allow(api_provider).to receive(:get_rated_disabilities)
          .and_raise(Common::Exceptions::ServiceUnavailable)
        expect(Rails.logger).not_to receive(:warn)
        expect { host.fetch_rated_disabilities_response(api_provider, invoker, user) }
          .to raise_error(Common::Exceptions::ServiceUnavailable)
      end

      context 'when the circuit is open (Breakers::OutageException)' do
        let(:lh_outage) { instance_double(Breakers::Outage, ended?: false) }
        let(:lh_breakers_service) { instance_double(Breakers::Service, latest_outage: lh_outage) }

        before do
          allow(VeteranVerification::Configuration.instance).to receive(:breakers_service)
            .and_return(lh_breakers_service)
        end

        it 'logs a warning and raises Breakers::OutageException' do
          expect(Rails.logger).to receive(:warn).with(
            'Skipping get_rated_disabilities due to service outage',
            { invoker: }
          )
          expect { host.fetch_rated_disabilities_response(api_provider, invoker, user) }
            .to raise_error(Breakers::OutageException)
        end

        it 'does not call the API provider' do
          allow(Rails.logger).to receive(:warn)
          expect(api_provider).not_to receive(:get_rated_disabilities)
          expect { host.fetch_rated_disabilities_response(api_provider, invoker, user) }
            .to raise_error(Breakers::OutageException)
        end

        it 'does not log a retry warn' do
          allow(Rails.logger).to receive(:warn)
          expect(Rails.logger).not_to receive(:warn).with(a_string_matching(/Retrying/), anything)
          expect { host.fetch_rated_disabilities_response(api_provider, invoker, user) }
            .to raise_error(Breakers::OutageException)
        end
      end
    end
  end
end
