# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Rack::Attack do
  include Rack::Test::Methods

  let(:headers) { { 'REMOTE_ADDR' => '1.2.3.4' } }

  def app
    Rails.application
  end

  before do
    Rack::Attack.cache.store.flushdb
  end

  before(:all) do
    Rack::Attack.cache.store = Rack::Attack::StoreProxy::RedisStoreProxy.new($redis)
  end

  describe Rack::Attack::Request do
    describe '#remote_ip' do
      subject(:remote_ip) { described_class.new(env).remote_ip }

      let(:env) do
        Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => remote_addr, 'HTTP_X_REAL_IP' => forwarded_ip)
      end
      let(:forwarded_ip) { '203.0.113.5' }

      context 'when HTTP_X_REAL_IP is sent by a trusted proxy' do
        let(:remote_addr) { '10.0.0.1' }

        before do
          allow(Rails.application.config.action_dispatch)
            .to receive(:trusted_proxies).and_return([IPAddr.new('10.0.0.0/8')])
        end

        it 'uses the IP forwarded by the trusted proxy' do
          expect(remote_ip).to eq(forwarded_ip)
        end
      end

      context 'when HTTP_X_REAL_IP is sent by an untrusted connection' do
        let(:remote_addr) { '203.0.113.9' }

        before do
          allow(Rails.application.config.action_dispatch)
            .to receive(:trusted_proxies).and_return([IPAddr.new('10.0.0.0/8')])
        end

        it 'ignores the spoofable header and falls back to the connecting IP' do
          expect(remote_ip).to eq(remote_addr)
        end
      end

      context 'when no trusted_proxies are configured' do
        let(:remote_addr) { '203.0.113.9' }

        it 'never trusts the header' do
          expect(remote_ip).to eq(remote_addr)
        end
      end

      context 'when only the literal X-Real-Ip env key is set (Rack::Test-style injection)' do
        let(:env) { Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '203.0.113.9', 'X-Real-Ip' => '198.51.100.1') }

        it 'still honors it for backward-compatible test env injection' do
          expect(remote_ip).to eq('198.51.100.1')
        end
      end
    end
  end

  describe '#throttled_response' do
    it 'adds X-RateLimit-* headers to the response' do
      post('/v0/limited', headers:)
      expect(last_response).not_to have_http_status(:too_many_requests)

      post('/v0/limited', headers:)
      expect(last_response).to have_http_status(:too_many_requests)
      expect(last_response.headers).to include(
        'X-RateLimit-Limit',
        'X-RateLimit-Remaining',
        'X-RateLimit-Reset'
      )
    end
  end

  describe 'throttle instrumentation' do
    it 'notifies RackAttack::ThrottleLogger with the throttled request' do
      post('/v0/limited', headers:)
      expect(last_response).not_to have_http_status(:too_many_requests)

      expect(RackAttack::ThrottleLogger).to receive(:log) do |request|
        expect(request.env['rack.attack.matched']).to eq('example/ip')
        expect(request.env['rack.attack.match_type']).to eq(:throttle)
      end

      post('/v0/limited', headers:)
      expect(last_response).to have_http_status(:too_many_requests)
    end
  end

  describe 'check_in/ip' do
    let(:data) { { data: 'foo', status: 200 } }

    context 'when more than 10 requests' do
      context 'when GET endpoint' do
        before do
          allow_any_instance_of(CheckIn::V2::Session).to receive(:authorized?).and_return(true)
          allow_any_instance_of(V2::Lorota::Service).to receive(:check_in_data).and_return(data)
          allow_any_instance_of(V2::Chip::Service).to receive(:set_echeckin_started).and_return(data)

          10.times do
            get('/check_in/v2/patient_check_ins/d602d9eb-9a31-484f-9637-13ab0b507e0d', headers:)

            expect(last_response).to have_http_status(:ok)
          end
        end

        it 'throttles with status 429' do
          get('/check_in/v2/patient_check_ins/d602d9eb-9a31-484f-9637-13ab0b507e0d', headers:)

          expect(last_response).to have_http_status(:too_many_requests)
        end
      end

      context 'when POST endpoint' do
        let(:post_params) do
          { patient_check_ins: { uuid: 'd602d9eb-9a31-484f-9637-13ab0b507e0d', appointment_ien: '450' } }
        end

        before do
          allow_any_instance_of(V2::Chip::Service).to receive(:create_check_in).and_return(data)

          10.times do
            post '/check_in/v2/patient_check_ins', post_params, headers

            expect(last_response).to have_http_status(:ok)
          end
        end

        it 'throttles with status 429' do
          post '/check_in/v2/patient_check_ins', post_params, headers

          expect(last_response).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'medical_copays/ip' do
    before do
      allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_copays).and_return([])
    end

    context 'when more than 20 requests' do
      before do
        20.times do
          get('/v0/medical_copays', headers:)

          expect(last_response).to have_http_status(:unauthorized)
        end
      end

      it 'throttles with status 429' do
        get('/v0/medical_copays', headers:)

        expect(last_response).to have_http_status(:too_many_requests)
      end
    end
  end

  describe 'facilities_api/v2/va/ip' do
    let(:endpoint) { '/facilities_api/v2/va' }
    let(:headers) { { 'X-Real-Ip' => '1.2.3.4' } }
    let(:limit) { 30 }

    before do
      limit.times do
        post endpoint, nil, headers
        expect(last_response).not_to have_http_status(:too_many_requests)
      end

      post endpoint, nil, other_headers
    end

    context 'response status for repeated requests from the same IP' do
      let(:other_headers) { headers }

      it 'limits requests' do
        expect(last_response).to have_http_status(:too_many_requests)
      end
    end

    context 'response status for request from different IP' do
      let(:other_headers) { { 'X-Real-Ip' => '4.3.2.1' } }

      it 'does not limit request' do
        expect(last_response).not_to have_http_status(:too_many_requests)
      end
    end
  end

  describe 'facilities_api/v2/ccp/ip' do
    let(:endpoint) { '/facilities_api/v2/ccp/provider' }
    let(:headers) { { 'X-Real-Ip' => '1.2.3.4' } }
    let(:limit) { 30 }

    before do
      limit.times do
        get endpoint, nil, headers
        expect(last_response).not_to have_http_status(:too_many_requests)
      end

      get endpoint, nil, other_headers
    end

    context 'response status for repeated requests from the same IP' do
      let(:other_headers) { headers }

      it 'limits requests' do
        expect(last_response).to have_http_status(:too_many_requests)
      end
    end

    context 'response status for request from different IP' do
      let(:other_headers) { { 'X-Real-Ip' => '4.3.2.1' } }

      it 'limits requests' do
        expect(last_response).not_to have_http_status(:too_many_requests)
      end
    end
  end

  describe 'facilities_api/v2/ccp/ip across sub-routes' do
    let(:limit) { 30 }

    it 'shares its limit between provider and pharmacy' do
      shared_headers = { 'X-Real-Ip' => '5.6.7.8' }

      limit.times do
        get '/facilities_api/v2/ccp/provider', nil, shared_headers
        expect(last_response).not_to have_http_status(:too_many_requests)
      end

      get '/facilities_api/v2/ccp/pharmacy', nil, shared_headers
      expect(last_response).to have_http_status(:too_many_requests)
    end
  end

  describe 'ask_va_api/zip_state_validation' do
    let(:endpoint) { '/ask_va_api/v0/zip_state_validation' }
    let(:headers) { { 'X-Real-Ip' => '1.2.3.4' } }
    let(:params) { { zip_code: '12345', state_code: 'VA' } }
    let(:limit) { 60 }

    before do
      allow(Settings).to receive(:vsp_environment).and_return('production')
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:ask_va_api_maintenance_mode).and_return(false)
      allow(AskVAApi::ZipStateValidation::ZipStateValidator).to receive(:call).and_return(
        Struct.new(:valid, :error_code, :error_message).new(true, nil, nil)
      )

      limit.times do
        post endpoint, params, headers
        expect(last_response).to have_http_status(:ok)
      end
    end

    it 'throttles with status 429' do
      post endpoint, params, headers

      expect(last_response).to have_http_status(:too_many_requests)
    end

    it 'does not throttle a different IP' do
      other_headers = { 'X-Real-Ip' => '4.3.2.1' }

      post endpoint, params, other_headers

      expect(last_response).to have_http_status(:ok)
    end
  end

  describe 'education_benefits_claims/v0/ip' do
    let(:endpoint) { '/v0/education_benefits_claims/1995' }
    let(:headers) { { 'X-Real-Ip' => '1.2.3.4' } }
    let(:limit) { 15 }

    before do
      limit.times do
        post endpoint, nil, headers
        expect(last_response).not_to have_http_status(:too_many_requests)
      end

      post endpoint, nil, other_headers
    end

    context 'response status for repeated requests from the same IP' do
      let(:other_headers) { headers }

      it 'limits requests' do
        expect(last_response).to have_http_status(:too_many_requests)
      end
    end

    context 'response status for request from different IP' do
      let(:other_headers) { { 'X-Real-Ip' => '4.3.2.1' } }

      it 'limits requests' do
        expect(last_response).not_to have_http_status(:too_many_requests)
      end
    end
  end

  describe 'vic rate-limits', run_at: 'Thu, 26 Dec 2015 15:54:20 GMT' do
    before do
      limit.times do
        post(endpoint, headers:)
        expect(last_response).not_to have_http_status(:too_many_requests)
      end

      post endpoint, headers:
    end

    context 'profile photo upload' do
      let(:limit) { 8 }
      let(:endpoint) { '/v0/vic/profile_photo_attachments' }

      it 'limits requests' do
        expect(last_response).to have_http_status(:too_many_requests)
      end
    end

    context 'supporting doc upload' do
      let(:limit) { 8 }
      let(:endpoint) { '/v0/vic/supporting_documentation_attachments' }

      it 'limits requests' do
        expect(last_response).to have_http_status(:too_many_requests)
      end
    end

    context 'form submission' do
      let(:limit) { 10 }
      let(:endpoint) { '/v0/vic/vic_submissions' }

      it 'limits requests' do
        expect(last_response).to have_http_status(:too_many_requests)
      end
    end
  end

  describe 'appointments' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/appointments', headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/appointments', headers:)).to have_http_status(:too_many_requests)
        end
      end

      context 'when POST endpoint' do
        let(:post_params) do
          { appt: { id: '12345' } }
        end

        before do
          30.times do
            expect(post('/vaos/v2/appointments', post_params:, headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(post('/vaos/v2/appointments', post_params:, headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'clinics' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/locations/983/clinics?clinic_ids=570,945',
                       headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/locations/983/clinics?clinic_ids=570,945',
                     headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'providers' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/providers', headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/providers', headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'patients' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/eligibility', headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/eligibility', headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'cc_eligibility' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/community_care/eligibility/PrimaryCare', headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/community_care/eligibility/PrimaryCare',
                     headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'scheduling_configurations' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/scheduling/configurations', headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/scheduling/configurations', headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'facilities' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/facilities', headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/facilities', headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'relationships' do
    context 'when more than 30 requests' do
      context 'when GET endpoint' do
        before do
          30.times do
            expect(get('/vaos/v2/relationships', headers:)).to have_http_status(:unauthorized)
          end
        end

        it 'throttles with status 429' do
          expect(get('/vaos/v2/relationships', headers:)).to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe 'BIO form endpoints (form214192, form21p530a, form210779, form212680)' do
    let(:headers) { { 'X-Real-Ip' => '1.2.3.4' } }
    let(:limit) { 30 }

    %w[
      /v0/form214192
      /v0/form21p530a
      /v0/form210779
      /v0/form212680
    ].each do |endpoint|
      context "when POST #{endpoint}" do
        before do
          limit.times do
            post endpoint, { form_data: '{}' }.to_json, headers.merge('CONTENT_TYPE' => 'application/json')
            expect(last_response).not_to have_http_status(:too_many_requests)
          end

          post endpoint, { form_data: '{}' }.to_json, other_headers.merge('CONTENT_TYPE' => 'application/json')
        end

        context 'response status for repeated requests from the same IP' do
          let(:other_headers) { headers }

          it 'throttles with status 429' do
            expect(last_response).to have_http_status(:too_many_requests)
          end
        end

        context 'response status for request from different IP' do
          let(:other_headers) { { 'X-Real-Ip' => '4.3.2.1' } }

          it 'does not throttle' do
            expect(last_response).not_to have_http_status(:too_many_requests)
          end
        end
      end
    end
  end

  describe 'profile/address_validation/ip' do
    # An invalid (empty) address returns 422 before any external call, so these
    # pre-throttle requests never reach VA-Profile.
    let(:endpoint) { '/v0/profile/address_validation' }
    let(:headers) { { 'X-Real-Ip' => '1.2.3.4', 'CONTENT_TYPE' => 'application/json' } }
    let(:params) { { address: {} }.to_json }
    let(:limit) { 30 }

    before do
      limit.times do
        post endpoint, params, headers
        expect(last_response).not_to have_http_status(:too_many_requests)
      end
    end

    it 'throttles with status 429' do
      post endpoint, params, headers

      expect(last_response).to have_http_status(:too_many_requests)
    end

    it 'does not throttle a different IP' do
      other_headers = { 'X-Real-Ip' => '4.3.2.1', 'CONTENT_TYPE' => 'application/json' }

      post endpoint, params, other_headers

      expect(last_response).not_to have_http_status(:too_many_requests)
    end

    it 'throttles a format-suffixed path so it cannot be used to bypass the limit' do
      post "#{endpoint}.json", params, headers

      expect(last_response).to have_http_status(:too_many_requests)
    end
  end
end
