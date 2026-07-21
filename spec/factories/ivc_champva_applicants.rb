# frozen_string_literal: true

FactoryBot.define do
  factory :ivc_champva_applicant do
    transaction_uuid { SecureRandom.uuid }
    applicant_icn { '0000001200603250V008079000000' }
    person_type { 'BENEFICIARY' }
    eligibility_resolved { false }
  end
end
