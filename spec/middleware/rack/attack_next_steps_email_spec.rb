# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack::Attack NextStepsEmail Throttling', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { 'REMOTE_ADDR' => '1.2.3.4' } }
  let(:base_path) { '/representation_management/v0/next_steps_email' }
  let(:email) { 'test@example.com' }
  let(:valid_params) do
    {
      next_steps_email: {
        email_address: email,
        first_name: 'Test',
        form_name: 'Form Name',
        form_number: '21-22',
        entity_type: 'individual',
        entity_id: '00000000-0000-0000-0000-000000000000'
      }
    }
  end

  before do
    @rack_attack_enabled_was = Rack::Attack.enabled
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.keys('rack::attack*').each { |k| Rack::Attack.cache.store.del(k) }
    allow(Flipper).to receive(:enabled?)
      .with(:appoint_a_representative_enable_confirmation_email)
      .and_return(true)
    allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
  end

  after do
    Rack::Attack.cache.store.keys('rack::attack*').each { |k| Rack::Attack.cache.store.del(k) }
    Rack::Attack.enabled = @rack_attack_enabled_was
  end

  describe 'representation_management/next_steps_email/ip throttle' do
    # These tests verify the IP throttle (5/min) in isolation. Requests are sent
    # as JSON with a unique email each time so the per-email throttle (3/hr)
    # hashes each to a different key and never accumulates.
    def ip_test_params(n = 0)
      valid_params.deep_merge(next_steps_email: { email_address: "user#{n}@example.com" })
    end

    it 'allows requests up to the rate limit (5 per minute)' do
      4.times do |i|
        post(base_path, params: ip_test_params(i), headers:, as: :json)
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    it 'throttles the 6th request within a minute from the same IP' do
      5.times { |i| post(base_path, params: ip_test_params(i), headers:, as: :json) }

      post(base_path, params: ip_test_params(99), headers:, as: :json)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'returns rate limit headers on throttled response' do
      6.times { |i| post(base_path, params: ip_test_params(i), headers:, as: :json) }

      expect(response.headers['X-RateLimit-Limit']).to eq('5')
      expect(response.headers['X-RateLimit-Remaining']).to eq('0')
      expect(response.headers['X-RateLimit-Reset']).to be_present
    end

    it 'counts requests from different IPs independently' do
      5.times { |i| post(base_path, params: ip_test_params(i), headers:, as: :json) }
      # 6th from same IP is throttled
      post(base_path, params: ip_test_params(99), headers:, as: :json)
      expect(response).to have_http_status(:too_many_requests)

      # Different IP is not throttled
      post(base_path, params: ip_test_params(100), headers: { 'REMOTE_ADDR' => '5.6.7.8' }, as: :json)
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it 'resets after a minute' do
      5.times { |i| post(base_path, params: ip_test_params(i), headers:, as: :json) }
      post(base_path, params: ip_test_params(99), headers:, as: :json)
      expect(response).to have_http_status(:too_many_requests)

      travel(61.seconds) do
        post(base_path, params: ip_test_params(200), headers:, as: :json)
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end
  end

  describe 'representation_management/next_steps_email/email throttle' do
    it 'allows up to 3 requests per hour to the same email' do
      2.times do
        post(base_path, params: valid_params, headers:, as: :json)
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    it 'throttles the 4th request per hour to the same email address' do
      3.times { post(base_path, params: valid_params, headers:, as: :json) }

      post(base_path, params: valid_params, headers:, as: :json)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts different email addresses independently' do
      3.times { post(base_path, params: valid_params, headers:, as: :json) }
      post(base_path, params: valid_params, headers:, as: :json)
      expect(response).to have_http_status(:too_many_requests)

      other_params = valid_params.deep_merge(next_steps_email: { email_address: 'other@example.com' })
      post(base_path, params: other_params, headers:, as: :json)
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it 'is case-insensitive on email address (A@example.com == a@example.com)' do
      3.times { post(base_path, params: valid_params, headers: { 'REMOTE_ADDR' => "1.2.3.#{_1 + 5}" }, as: :json) }

      upper_params = valid_params.deep_merge(next_steps_email: { email_address: email.upcase })
      post(base_path, params: upper_params, headers: { 'REMOTE_ADDR' => '9.9.9.9' }, as: :json)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'does not crash when request body is not valid JSON' do
      # Non-JSON body triggers rescue which falls back to IP as throttle key.
      # The per-email throttle (limit 3/hr) fires first since it also keys on IP
      # as fallback, so the 4th request is throttled (not the 6th).
      3.times do
        post(base_path, params: 'not-json', headers: headers.merge('CONTENT_TYPE' => 'text/plain'))
        expect(response).not_to have_http_status(:too_many_requests)
      end

      post(base_path, params: 'not-json', headers: headers.merge('CONTENT_TYPE' => 'text/plain'))
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
