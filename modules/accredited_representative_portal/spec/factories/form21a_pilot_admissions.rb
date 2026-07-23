# frozen_string_literal: true

FactoryBot.define do
  factory :form21a_pilot_admission, class: 'AccreditedRepresentativePortal::Form21aPilotAdmission' do
    association :user_account
    status { 'started' }

    trait :submitted do
      status { 'submitted' }
      submitted_at { Time.current }
    end
  end
end
