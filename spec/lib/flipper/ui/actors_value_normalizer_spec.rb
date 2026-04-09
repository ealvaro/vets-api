# frozen_string_literal: true

require 'rails_helper'
require 'flipper/ui/actors_value_normalizer'

RSpec.describe Flipper::UI::ActorsValueNormalizer do
  let(:inner_app) { ->(env) { [200, {}, [env.to_json]] } }
  let(:middleware) { described_class.new(inner_app) }

  def post_env(path, params = {})
    Rack::MockRequest.env_for(
      path,
      method: 'POST',
      params:
    )
  end

  def get_env(path)
    Rack::MockRequest.env_for(path, method: 'GET')
  end

  context 'when POST to an actors endpoint for a user-type feature' do
    before do
      stub_const('FLIPPER_FEATURE_CONFIG', { 'features' => { 'my_feature' => { 'actor_type' => 'user' } } })
      stub_const('FLIPPER_ACTOR_STRING', 'cookie_id')
    end

    it 'downcases a single email value' do
      env = post_env('/flipper/features/my_feature/actors', 'value' => 'John.Doe@VA.GOV')
      middleware.call(env)
      expect(env['rack.request.form_hash']['value']).to eq('john.doe@va.gov')
    end

    it 'downcases comma-separated email values' do
      env = post_env('/flipper/features/my_feature/actors', 'value' => 'John@VA.GOV, Jane@VA.GOV')
      middleware.call(env)
      expect(env['rack.request.form_hash']['value']).to eq('john@va.gov,jane@va.gov')
    end

    it 'downcases UUID values' do
      env = post_env('/flipper/features/my_feature/actors', 'value' => 'ABC123-DEF456')
      middleware.call(env)
      expect(env['rack.request.form_hash']['value']).to eq('abc123-def456')
    end

    it 'preserves other params' do
      env = post_env('/flipper/features/my_feature/actors', 'value' => 'TEST@VA.GOV', 'operation' => 'enable')
      middleware.call(env)
      expect(env['rack.request.form_hash']['operation']).to eq('enable')
    end
  end

  context 'when POST to an actors endpoint for a cookie_id-type feature' do
    before do
      stub_const('FLIPPER_FEATURE_CONFIG',
                 { 'features' => { 'cookie_feature' => { 'actor_type' => 'cookie_id' } } })
      stub_const('FLIPPER_ACTOR_STRING', 'cookie_id')
    end

    it 'does not modify the value' do
      env = post_env('/flipper/features/cookie_feature/actors', 'value' => 'SomeCaseSensitiveCookieId')
      middleware.call(env)
      expect(env['rack.request.form_hash']).to be_nil
    end
  end

  context 'when feature is not in config (defaults to user)' do
    before do
      stub_const('FLIPPER_FEATURE_CONFIG', { 'features' => {} })
      stub_const('FLIPPER_ACTOR_STRING', 'cookie_id')
    end

    it 'downcases the value' do
      env = post_env('/flipper/features/unknown_feature/actors', 'value' => 'Test@VA.GOV')
      middleware.call(env)
      expect(env['rack.request.form_hash']['value']).to eq('test@va.gov')
    end
  end

  context 'when POST to a non-actors endpoint' do
    it 'does not modify the value param' do
      env = post_env('/flipper/features/my_feature/boolean', 'value' => 'TRUE')
      middleware.call(env)
      expect(env['rack.request.form_hash']).to be_nil
    end
  end

  context 'when GET to an actors endpoint' do
    it 'does not modify anything' do
      env = get_env('/flipper/features/my_feature/actors')
      status, = middleware.call(env)
      expect(status).to eq(200)
    end
  end
end
