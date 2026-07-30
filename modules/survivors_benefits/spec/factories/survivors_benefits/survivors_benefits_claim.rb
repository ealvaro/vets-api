# frozen_string_literal: true

FactoryBot.define do
  factory :survivors_benefits_claim, class: 'SurvivorsBenefits::SavedClaim' do
    form_id { '21P-534EZ' }
    form do
      {
        veteranFullName: {
          first: 'John',
          middle: 'Edmund',
          last: 'Doe'
        },
        claimantFullName: {
          first: 'Derrick',
          middle: 'A',
          last: 'Stewart'
        },
        veteranSocialSecurityNumber: '333224444',
        statementOfTruthCertified: true,
        statementOfTruthSignature: 'John Edmund Doe'
      }.to_json
    end

    # A custodian filing on behalf of a child under 18. claimant* describes the child; the
    # custodian's own details arrive under filingCustodian* plus the childRelationship free text.
    trait :with_custodian do
      form do
        {
          veteranFullName: {
            first: 'John',
            middle: 'Edmund',
            last: 'Doe'
          },
          claimantFullName: {
            first: 'Derrick',
            middle: 'A',
            last: 'Stewart'
          },
          claimantRelationship: 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
          filingCustodianFullName: {
            first: 'Jane',
            middle: 'Quincy',
            last: 'Custodian'
          },
          childRelationship: 'Mother',
          filingCustodianAddress: {
            street: '123 Main St',
            street2: 'Apt 4B',
            city: 'Springfield',
            state: 'IL',
            postalCode: '62704',
            country: 'USA'
          },
          filingCustodianEmail: 'jane.custodian@example.com',
          veteranSocialSecurityNumber: '333224444',
          statementOfTruthCertified: true,
          statementOfTruthSignature: 'Jane Quincy Custodian'
        }.to_json
      end
    end
  end
end
