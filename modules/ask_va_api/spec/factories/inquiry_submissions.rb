# frozen_string_literal: true

FactoryBot.define do
  factory :ask_va_api_inquiry_submission, class: 'AskVAApi::InquirySubmission' do
    crm_message_id { nil }
    inquiry_number { nil }
    request_id { SecureRandom.uuid }

    trait :with_message_id do
      crm_message_id { 'cb0dd954-ef25-4e56-b0d9-41925e5a190c' }
    end

    trait :with_message_id_and_inquiry_number do
      crm_message_id { 'cb0dd954-ef25-4e56-b0d9-41925e5a190c' }
      inquiry_number { '530d56a8-affd-ee11-a1fe-001dd8094ff1' }
    end
  end
end
