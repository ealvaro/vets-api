# frozen_string_literal: true

RSpec.shared_context 'coe claim form validation' do
  subject(:claim) { described_class.new(form: form_json) }

  let(:loan_history_base) do
    {
      'certificateUse' => 'HOME_PURCHASE',
      'hadPriorLoans' => 'false',
      'currentAddressWasVAHomeLoan' => 'false',
      'entitlementRestoration' => 'ONE_TIME_RESTORATION',
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
        'preDischargeClaim' => 'false',
        'purpleHeartRecipient' => 'false',
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

  let(:form_json) { valid_form_hash.to_json }

  def error_attributes(claim_record)
    claim_record.errors.map { |e| e.attribute.to_s }
  end
end
