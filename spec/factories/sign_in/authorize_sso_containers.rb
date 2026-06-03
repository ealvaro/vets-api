# frozen_string_literal: true

FactoryBot.define do
  factory :authorize_sso_container, class: 'SignIn::AuthorizeSSOContainer' do
    uuid { SecureRandom.uuid }
    client_id { create(:client_config).client_id }
    code_challenge { Base64.urlsafe_encode64(SecureRandom.hex) }
    code_challenge_method { 'S256' }
    client_state { SecureRandom.hex }
    app_name { 'some-app' }
    nonce { SecureRandom.hex }
  end
end
