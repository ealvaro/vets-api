# frozen_string_literal: true

FactoryBot.define do
  factory :remediation_batch_upload_item do
    sequence(:submission_id) { |n| "SUB-#{n.to_s.rjust(6, '0')}" }
    s3_bucket { 'dsva-vetsgov-remediation-prod' }
    sequence(:s3_key) { |n| "documents/#{n}/evidence.pdf" }
    document_type_id { 131 }
    submission_datetime { 1.week.ago }
    status { 'pending' }
    retry_count { 0 }

    trait :completed do
      status { 'completed' }
      completed_at { Time.current }
      claims_evidence_file_uuid { SecureRandom.uuid }
    end

    trait :failed do
      status { 'failed' }
      error_class { 'Aws::S3::Errors::NoSuchKey' }
      error_message { 'The specified key does not exist.' }
      retry_count { 1 }
    end

    trait :exhausted do
      status { 'failed' }
      error_class { 'Faraday::ServerError' }
      error_message { '500 Internal Server Error' }
      retry_count { 3 }
    end

    trait :downloading do
      status { 'downloading' }
      started_at { Time.current }
    end

    trait :uploading do
      status { 'uploading' }
      started_at { Time.current }
    end

    trait :stale_downloading do
      status { 'downloading' }
      started_at { 20.minutes.ago }
    end

    trait :stale_uploading do
      status { 'uploading' }
      started_at { 20.minutes.ago }
    end
  end
end
