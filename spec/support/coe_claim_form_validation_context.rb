# frozen_string_literal: true

RSpec.shared_context 'coe claim form validation' do
  subject(:claim) { described_class.new(form: form_json) }

  let(:loan_history_base) do
    {
      'certificateUse' => 'HOME_PURCHASE',
      'hadPriorLoans' => 'false',
      'relevantPriorLoans' => []
    }
  end

  let(:valid_form_hash) do
    {
      'version' => 2,
      'fullName' => { 'first' => 'Jane', 'middle' => '', 'last' => 'Doe' },
      'dateOfBirth' => '1990-05-15',
      'ssnLast4' => '1234',
      'veteran' => {
        'mailingAddress' => {
          'addressLine1' => '123 Main St',
          'addressLine2' => '',
          'addressLine3' => '',
          'city' => 'Richmond',
          'stateCode' => 'VA',
          'zipCode' => '23219'
        },
        'homePhone' => { 'areaCode' => '800', 'countryCode' => '1', 'phoneNumber' => '5551234' },
        'email' => { 'emailAddress' => 'jane.doe@example.com' }
      },
      'militaryHistory' => {
        'status' => 'VETERAN',
        'separatedDueToDisability' => 'false',
        'periodsOfService' => [
          {
            'serviceBranch' => 'ARMY',
            'dateRange' => {
              'from' => '2000-01-01T00:00:00.000Z',
              'to' => '2005-01-01T00:00:00.000Z'
            }
          }
        ]
      },
      'loanHistory' => loan_history_base,
      'privacyAgreementAccepted' => true
    }
  end

  let(:valid_v3_prior_loan) do
    {
      'naturalDisaster' => {
        'affected' => true,
        'dateOfLoss' => '2004-02-01T00:00:00.000Z'
      },
      'entitlementRestoration' => 'CASH_OUT_REFINANCE',
      'loanDate' => '2005-03-01T00:00:00.000Z',
      'vaLoanNumber' => '123456789000',
      'propertyAddress' => {
        'country' => 'USA',
        'street1' => '350 Fifth Ave',
        'city' => 'New York',
        'state' => 'NY',
        'postalCode' => '10118'
      }
    }
  end

  let(:valid_v3_form_hash) do
    {
      'version' => 3,
      'fullName' => { 'first' => 'Glen', 'middle' => 'F', 'last' => 'Mitchell' },
      'veteran' => {
        'mailingAddress' => {
          'addressLine1' => '350 Fifth Ave',
          'addressLine2' => '',
          'addressLine3' => '',
          'city' => 'New York',
          'stateCode' => 'NY',
          'zipCode' => '10118'
        },
        'homePhone' => { 'areaCode' => '208', 'countryCode' => '1', 'phoneNumber' => '5555554' },
        'email' => { 'emailAddress' => 'test222@test.com' }
      },
      'militaryHistory' => {
        'status' => 'ADSM',
        'separatedDueToDisability' => true,
        'preDischargeClaim' => true,
        'purpleHeartRecipient' => true,
        'periodsOfService' => [
          {
            'serviceBranch' => 'AF',
            'dateRange' => {
              'from' => '2003-02-01T00:00:00.000Z',
              'to' => '2004-06-01T00:00:00.000Z'
            }
          }
        ]
      },
      'loanHistory' => {
        'certificateUse' => 'HOME_PURCHASE',
        'hadPriorLoans' => true,
        'relevantPriorLoans' => [valid_v3_prior_loan]
      },
      'privacyAgreementAccepted' => true
    }
  end

  let(:form_json) { valid_form_hash.to_json }

  def error_attributes(claim_record)
    claim_record.errors.map { |e| e.attribute.to_s }
  end
end
