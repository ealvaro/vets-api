# frozen_string_literal: true

FactoryBot.define do
  factory :digital_forms_api_submission, class: 'DigitalFormsApi::Submission' do
    form_id { '21-686c' }
    bip_submission_id { SecureRandom.uuid }
    reference_data { { 'ep_code' => '130', 'claim_label' => '130DPEBNAJRE' } }
  end
end
