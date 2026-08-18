# frozen_string_literal: true

FactoryBot.define do
  factory :session_record, class: 'SignIn::SessionRecord' do
    handle { SecureRandom.uuid }
    client_id { create(:client_config).client_id }
    user_account { create(:user_account) }
    sign_in_ip { Faker::Internet.ip_v4_address }
    user_agent { Faker::Internet.user_agent }
    last_activity_at { Time.zone.now }
    signed_out_at { nil }
    device_description { nil }
    csp_type { nil }
    browser { nil }
    location { nil }
    created_at { Time.zone.now }
  end
end
