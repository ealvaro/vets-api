# frozen_string_literal: true

FactoryBot.define do
  factory :saved_claim_intent_to_file,
          class: 'AccreditedRepresentativePortal::SavedClaim::BenefitsClaims::IntentToFile' do
    guid { SecureRandom.uuid }

    form do
      {
        'veteran' => {
          'name' => { 'first' => 'John', 'last' => 'Doe' },
          'ssn' => '123456789',
          'dateOfBirth' => '1980-12-31'
        },
        'dependent' => {
          'name' => { 'first' => 'Jane', 'last' => 'Doe' },
          'ssn' => '987654321',
          'dateOfBirth' => '2010-01-01'
        },
        'benefitType' => 'compensation'
      }.to_json
    end
  end
end
