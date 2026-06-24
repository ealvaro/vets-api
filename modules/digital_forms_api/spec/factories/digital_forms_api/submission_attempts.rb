# frozen_string_literal: true

FactoryBot.define do
  factory :digital_forms_api_submission_attempt, class: 'DigitalFormsApi::SubmissionAttempt' do
    association :submission, factory: :digital_forms_api_submission
    status { 'pending' }

    trait :accepted do
      status { 'accepted' }
    end

    trait :failed do
      status { 'failed' }
    end
  end
end
