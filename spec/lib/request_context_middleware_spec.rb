# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RequestContextMiddleware do
  include ActiveSupport::Testing::TimeHelpers

  subject(:middleware) { described_class.new(inner_app, signing_key:) }

  let(:inner_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  let(:signing_key) { 'test-signing-key' }

  let(:env) { Rack::MockRequest.env_for("#{scheme}://example.com/v0/user", rack_env) }
  let(:scheme) { 'https' }
  let(:rack_env) do
    {
      'HTTP_X_DEVICE_ID' => device_id,
      'HTTP_X_VISIT_ID' => visit_id,
      'HTTP_COOKIE' => http_cookie
    }.compact
  end
  let(:verifier) { ActiveSupport::MessageVerifier.new(signing_key, digest: 'SHA256') }
  let(:http_cookie) { nil }
  let(:device_id) { nil }
  let(:visit_id) { nil }

  describe '#call' do
    context 'when no ID headers or cookies are provided' do
      it 'generates new IDs' do
        middleware.call(env)

        expect(env[described_class::DEVICE_ENV_KEY]).to be_present
        expect(env[described_class::VISIT_ENV_KEY]).to be_present
      end
    end

    context 'when unsigned IDs are provided' do
      let(:device_id) { 'unsigned-device-id' }
      let(:visit_id) { 'unsigned-visit-id' }
      let(:http_cookie) { "did=#{device_id}; vid=#{visit_id}" }

      let(:expected_device_id) { 'new-device-id' }
      let(:expected_visit_id) { 'new-visit-id' }

      before do
        allow(SecureRandom).to receive(:uuid).and_return(expected_device_id, expected_visit_id)
      end

      it 'generates new IDs' do
        middleware.call(env)

        expect(env[described_class::DEVICE_ENV_KEY]).to eq(expected_device_id)
        expect(env[described_class::VISIT_ENV_KEY]).to eq(expected_visit_id)
      end
    end

    context 'when only signed headers are provided (no cookies)' do
      let(:device_id) { verifier.generate('header-device-id') }
      let(:visit_id) { verifier.generate('header-visit-id') }

      it 'resolves IDs from headers' do
        middleware.call(env)

        expect(env[described_class::DEVICE_ENV_KEY]).to eq('header-device-id')
        expect(env[described_class::VISIT_ENV_KEY]).to eq('header-visit-id')
      end
    end

    context 'when only signed cookies are provided (no headers)' do
      let(:http_cookie) { "did=#{verifier.generate('cookie-device-id')}; vid=#{verifier.generate('cookie-visit-id')}" }

      it 'resolves IDs from cookies' do
        middleware.call(env)

        expect(env[described_class::DEVICE_ENV_KEY]).to eq('cookie-device-id')
        expect(env[described_class::VISIT_ENV_KEY]).to eq('cookie-visit-id')
      end
    end

    context 'when header and cookie contain different signed values' do
      let(:device_id) { verifier.generate('header-device-id') }
      let(:visit_id) { verifier.generate('header-visit-id') }
      let(:http_cookie) { "did=#{verifier.generate('cookie-device-id')}; vid=#{verifier.generate('cookie-visit-id')}" }

      it 'prefers the cookie over the header' do
        middleware.call(env)

        expect(env[described_class::DEVICE_ENV_KEY]).to eq('cookie-device-id')
        expect(env[described_class::VISIT_ENV_KEY]).to eq('cookie-visit-id')
      end
    end

    context 'cookie directives' do
      let(:response) { middleware.call(env) }

      context 'with ssl' do
        it 'sets path, httponly, samesite, expires, and secure' do
          cookie_headers = Array(response[1]['set-cookie'])

          %w[did vid].each do |name|
            expect(cookie_headers).to include(match(%r{^#{name}=.*;\s*path=/}i))
            expect(cookie_headers).to include(match(/^#{name}=.*;\s*httponly\b/i))
            expect(cookie_headers).to include(match(/^#{name}=.*;\s*samesite=lax\b/i))
            expect(cookie_headers).to include(match(/^#{name}=.*;\s*expires=/i))
            expect(cookie_headers).to include(match(/^#{name}=.*;\s*secure\b/i))
          end
        end
      end

      context 'without ssl' do
        let(:scheme) { 'http' }

        it 'sets path, httponly, samesite, and expires but not secure' do
          cookie_headers = Array(response[1]['set-cookie'])

          %w[did vid].each do |name|
            expect(cookie_headers).to include(match(%r{^#{name}=.*;\s*path=/}i))
            expect(cookie_headers).to include(match(/^#{name}=.*;\s*httponly\b/i))
            expect(cookie_headers).to include(match(/^#{name}=.*;\s*samesite=lax\b/i))
            expect(cookie_headers).to include(match(/^#{name}=.*;\s*expires=/i))
            expect(cookie_headers).not_to include(match(/^#{name}=.*;\s*secure\b/i))
          end
        end
      end
    end

    it 'sets response headers with signed IDs' do
      response = middleware.call(env)
      headers = response[1]

      expect(verifier.verified(headers[described_class::DEVICE_HEADER])).to eq(env[described_class::DEVICE_ENV_KEY])
      expect(verifier.verified(headers[described_class::VISIT_HEADER])).to eq(env[described_class::VISIT_ENV_KEY])
    end

    it 'sets expires using the configured TTLs' do
      travel_to(Time.zone.parse('2026-02-26 12:00:00')) do
        _, headers = middleware.call(env)
        cookies = Array(headers['set-cookie'])

        expect(cookies).to include(match(/^did=.*expires=.*2046/i))
        expect(cookies).to include(match(/^vid=.*expires=.*2026/i))
      end
    end
  end

  describe 'signing key rotation' do
    let(:old_key) { 'old-signing-key' }
    let(:new_key) { 'new-signing-key' }
    let(:rotated_middleware) { described_class.new(inner_app, signing_key: new_key, rotated_signing_keys: [old_key]) }

    context 'with a rotated key' do
      let(:old_verifier) { ActiveSupport::MessageVerifier.new(old_key, digest: 'SHA256') }
      let(:device_uuid) { 'a1b2c3d4-0000-0000-0000-000000000001' }
      let(:visit_uuid) { 'a1b2c3d4-0000-0000-0000-000000000002' }
      let(:env) do
        Rack::MockRequest.env_for(
          'https://example.com/v0/user',
          'HTTP_COOKIE' => "did=#{old_verifier.generate(device_uuid)}; vid=#{old_verifier.generate(visit_uuid)}"
        )
      end

      it 'accepts cookies signed with the old key' do
        rotated_middleware.call(env)

        expect(env[described_class::DEVICE_ENV_KEY]).to eq(device_uuid)
        expect(env[described_class::VISIT_ENV_KEY]).to eq(visit_uuid)
      end

      it 're-signs with the new key' do
        _, headers = rotated_middleware.call(env)
        cookies = Array(headers['set-cookie'])

        new_verifier = ActiveSupport::MessageVerifier.new(new_key, digest: 'SHA256')
        did_value = Rack::Utils.parse_cookies_header(cookies.find { |c| c.start_with?('did=') })['did']
        vid_value = Rack::Utils.parse_cookies_header(cookies.find { |c| c.start_with?('vid=') })['vid']
        expect(new_verifier.verified(did_value)).to eq(device_uuid)
        expect(new_verifier.verified(vid_value)).to eq(visit_uuid)
      end
    end

    context 'with an unknown key' do
      let(:unknown_verifier) { ActiveSupport::MessageVerifier.new('unknown-key', digest: 'SHA256') }
      let(:env) do
        Rack::MockRequest.env_for(
          'https://example.com/v0/user',
          'HTTP_COOKIE' => "did=#{unknown_verifier.generate('fake-1')}; vid=#{unknown_verifier.generate('fake-2')}"
        )
      end

      it 'rejects the cookies and generates fresh IDs' do
        allow(SecureRandom).to receive(:uuid).and_return('fresh-uuid-1', 'fresh-uuid-2')

        rotated_middleware.call(env)

        expect(env[described_class::DEVICE_ENV_KEY]).to eq('fresh-uuid-1')
        expect(env[described_class::VISIT_ENV_KEY]).to eq('fresh-uuid-2')
      end
    end
  end

  describe RequestContextExtension do
    let(:env) do
      env = Rack::MockRequest.env_for('https://example.com/')
      env[RequestContextMiddleware::DEVICE_ENV_KEY] = 'dev-123'
      env[RequestContextMiddleware::VISIT_ENV_KEY]  = 'visit-456'
      env
    end
    let(:req) { ActionDispatch::Request.new(env) }

    it 'adds #device_id and #visit_id to ActionDispatch::Request' do
      expect(req.device_id).to eq('dev-123')
      expect(req.visit_id).to eq('visit-456')
    end
  end
end
