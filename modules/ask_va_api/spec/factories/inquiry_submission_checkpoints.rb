# frozen_string_literal: true

FactoryBot.define do
  factory :ask_va_api_inquiry_submission_checkpoint, class: 'AskVAApi::InquirySubmissionCheckpoint' do
    association :inquiry_submission, factory: :ask_va_api_inquiry_submission
    checkpoint_type { :inbound_submission }
    payload { { foo: 'bar' } }

    trait :outbound_submission do
      checkpoint_type { :outbound_submission }
    end

    trait :crm_response do
      checkpoint_type { :crm_response }
    end
  end
end
