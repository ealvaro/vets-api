# frozen_string_literal: true

FactoryBot.define do
  factory :clear_code_container, class: 'SignIn::Clear::CodeContainer' do
    state { SecureRandom.hex }
    code_verifier { SecureRandom.urlsafe_base64(64) }
  end
end
