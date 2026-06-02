# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavedClaim::CoeClaim, type: :model do
  include_context 'coe claim form validation'

  def mutate_form
    h = valid_form_hash.deep_dup
    yield h
    h.to_json
  end

  let(:valid_prior_loan) do
    {
      'vaLoanNumber' => '123456789012',
      'entitlementRestoration' => 'ONE_TIME_RESTORATION',
      'loanDate' => '2010-01-01T00:00:00.000Z',
      'propertyAddress' => {
        'country' => 'USA',
        'street1' => '1',
        'city' => 'X',
        'state' => 'VA',
        'postalCode' => '20152'
      }
    }
  end

  def form_with_prior_loans(loans)
    mutate_form do |h|
      h['loanHistory']['hadPriorLoans'] = 'true'
      h['loanHistory']['relevantPriorLoans'] = loans
    end
  end

  def mutate_prior_loan
    loan = valid_prior_loan.deep_dup
    yield loan
    mutate_form do |h|
      h['loanHistory']['hadPriorLoans'] = 'true'
      h['loanHistory']['relevantPriorLoans'] = [loan]
    end
  end

  def error_messages(claim_record, attribute)
    claim_record.errors.select { |e| e.attribute.to_s == attribute }.map(&:message)
  end

  describe '#form_matches_schema' do
    it 'returns early when form is not a string' do
      claim = described_class.new(form: valid_form_hash.to_json)
      allow(claim).to receive(:form_is_string).and_return(false)
      expect(claim).not_to receive(:validate_coe_rebuild_form)
      claim.send(:form_matches_schema)
    end

    it 'does not run validate_coe_rebuild_form for v1 forms' do
      claim = described_class.new(form: valid_form_hash.merge('version' => 1).to_json)
      allow(claim).to receive(:form_is_string).and_return(true)
      expect(claim).not_to receive(:validate_coe_rebuild_form)
      claim.send(:form_matches_schema)
    end

    it 'calls validate_coe_rebuild_form for v2 forms when the form is a string' do
      claim = described_class.new(form: valid_form_hash.to_json)
      allow(claim).to receive(:form_is_string).and_return(true)
      expect(claim).to receive(:validate_coe_rebuild_form).and_call_original
      claim.send(:form_matches_schema)
    end

    it 'treats missing version as v1 and skips v2 validation' do
      claim = described_class.new(form: valid_form_hash.except('version').to_json)
      allow(claim).to receive(:form_is_string).and_return(true)
      expect(claim).not_to receive(:validate_coe_rebuild_form)
      claim.send(:form_matches_schema)
    end
  end

  describe '#lgy_row_property_owned?' do
    it 'returns true when propertyOwned key is absent' do
      claim = described_class.new(form: valid_form_hash.to_json)
      expect(claim.send(:lgy_row_property_owned?, {})).to be true
    end

    it 'returns false when propertyOwned is false-like' do
      claim = described_class.new(form: valid_form_hash.to_json)
      expect(claim.send(:lgy_row_property_owned?, { 'propertyOwned' => false })).to be false
    end

    it 'returns true when propertyOwned is true-like' do
      claim = described_class.new(form: valid_form_hash.to_json)
      expect(claim.send(:lgy_row_property_owned?, { 'propertyOwned' => 'true' })).to be true
    end
  end

  describe 'COE v2 field validation' do
    context 'with a complete valid payload' do
      it 'passes validation' do
        expect(claim.validate).to be true
        expect(claim.errors).to be_empty
      end
    end

    describe '#rebuild_form_version?' do
      it 'safely returns false when parsed_form is malformed' do
        claim = described_class.new(form: valid_form_hash.to_json)
        allow(claim).to receive(:parsed_form).and_raise(JSON::ParserError)

        expect(claim.send(:rebuild_form_version?)).to be false
      end

      it 'returns true for v2 and v3 forms' do
        v2_claim = described_class.new(form: valid_form_hash.merge('version' => 2).to_json)
        v3_claim = described_class.new(form: valid_v3_form_hash.to_json)

        expect(v2_claim.send(:rebuild_form_version?)).to be true
        expect(v3_claim.send(:rebuild_form_version?)).to be true
      end

      it 'returns false for v1 forms' do
        v1_claim = described_class.new(form: valid_form_hash.merge('version' => 1).to_json)

        expect(v1_claim.send(:rebuild_form_version?)).to be false
      end
    end

    it 'validates a structurally complete v2 claim without adding field errors' do
      valid = described_class.new(form: valid_form_hash.merge('version' => 2).to_json)
      expect(valid.validate).to be true
      expect(valid.errors).to be_empty
    end

    it 'rejects a structurally bad v2 payload with field errors' do
      invalid = described_class.new(form: valid_form_hash.merge('version' => 2).except('fullName').to_json)
      expect(invalid.validate).to be false
      expect(invalid.errors).not_to be_empty
      expect(error_attributes(invalid)).to include('/fullName')
    end

    context 'with a valid files2 attachment' do
      let(:form_json) do
        mutate_form { |h| h['files2'] = [{ 'confirmationCode' => 'b', 'type' => 'application/pdf' }] }
      end

      it 'passes validation' do
        expect(claim.validate).to be true
        expect(claim.errors).to be_empty
      end
    end

    it 'logs when validation fails' do
      allow(Rails.logger).to receive(:error)
      expect(claim.validate).to be true
      expect(Rails.logger).not_to have_received(:error)

      invalid = described_class.new(form: valid_form_hash.except('fullName').to_json)
      invalid.validate
      expect(Rails.logger).to have_received(:error).with(
        'SavedClaim form did not pass validation',
        hash_including(:errors)
      )
    end

    context 'when a required top-level field is missing' do
      let(:form_json) { valid_form_hash.except('fullName').to_json }

      it 'records a required error' do
        claim.validate
        expect(error_attributes(claim)).to include('/fullName')
      end
    end

    context 'when privacyAgreementAccepted is not true' do
      let(:form_json) { mutate_form { |h| h['privacyAgreementAccepted'] = false } }

      it 'rejects the payload' do
        claim.validate
        expect(error_attributes(claim)).to include('/privacyAgreementAccepted')
      end
    end

    context 'when fullName is not an object' do
      let(:form_json) { mutate_form { |h| h['fullName'] = 'oops' } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/fullName')
      end
    end

    context 'when veteran is not an object' do
      let(:form_json) { mutate_form { |h| h['veteran'] = [] } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran')
      end
    end

    context 'when fullName is an empty string' do
      let(:form_json) { mutate_form { |h| h['fullName'] = '' } }

      it 'records both required and object type errors' do
        claim.validate
        messages = error_messages(claim, '/fullName')
        expect(messages).to include('is required')
        expect(messages).to include('must be an object')
      end
    end

    context 'when veteran is an empty string' do
      let(:form_json) { mutate_form { |h| h['veteran'] = '' } }

      it 'records both required and object type errors' do
        claim.validate
        messages = error_messages(claim, '/veteran')
        expect(messages).to include('is required')
        expect(messages).to include('must be an object')
      end
    end

    context 'when militaryHistory is an empty string' do
      let(:form_json) { mutate_form { |h| h['militaryHistory'] = '' } }

      it 'records both required and object type errors' do
        claim.validate
        messages = error_messages(claim, '/militaryHistory')
        expect(messages).to include('is required')
        expect(messages).to include('must be an object')
      end
    end

    context 'when loanHistory is an empty string' do
      let(:form_json) { mutate_form { |h| h['loanHistory'] = '' } }

      it 'records both required and object type errors' do
        claim.validate
        messages = error_messages(claim, '/loanHistory')
        expect(messages).to include('is required')
        expect(messages).to include('must be an object')
      end
    end

    context 'when militaryHistory periodsOfService is not an array' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'] = {} } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService')
      end
    end

    context 'when militaryHistory periodsOfService is an empty string' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'] = '' } }

      it 'records both required and array type errors' do
        claim.validate
        messages = error_messages(claim, '/militaryHistory/periodsOfService')
        expect(messages).to include('is required')
        expect(messages).to include('must be an array')
      end
    end

    context 'when militaryHistory periodsOfService is empty' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'] = [] } }

      it 'requires at least one period' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService')
      end
    end

    context 'when fullName first is too long' do
      let(:form_json) { mutate_form { |h| h['fullName']['first'] = 'x' * 31 } }

      it 'records a length error' do
        claim.validate
        expect(error_attributes(claim)).to include('/fullName/first')
      end
    end

    context 'when veteran home phone is not 10 digits' do
      let(:form_json) do
        mutate_form do |h|
          h['veteran']['homePhone'] = {
            'areaCode' => '800',
            'countryCode' => '1',
            'phoneNumber' => '55512345'
          }
        end
      end

      it 'records a phone format error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/homePhone')
      end
    end

    context 'when homePhone areaCode is not a string' do
      let(:form_json) { mutate_form { |h| h['veteran']['homePhone']['areaCode'] = 800 } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/homePhone/areaCode')
      end
    end

    context 'when veteran email is not a valid address' do
      let(:form_json) { mutate_form { |h| h['veteran']['email']['emailAddress'] = 'not-an-email' } }

      it 'records an email format error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/email/emailAddress')
      end
    end

    context 'when veteran email is too long' do
      let(:form_json) { mutate_form { |h| h['veteran']['email']['emailAddress'] = "#{'a' * 251}@x.com" } }

      it 'records a length error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/email/emailAddress')
      end
    end

    context 'when veteran emailAddress is not a string' do
      let(:form_json) { mutate_form { |h| h['veteran']['email']['emailAddress'] = 12_345 } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/email/emailAddress')
      end
    end

    context 'when veteran mailingAddress stateCode is not a valid code' do
      let(:form_json) { mutate_form { |h| h['veteran']['mailingAddress']['stateCode'] = 'ZZ' } }

      it 'records a state error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/mailingAddress/stateCode')
      end
    end

    context 'when veteran mailingAddress zipCode is invalid' do
      let(:form_json) { mutate_form { |h| h['veteran']['mailingAddress']['zipCode'] = 'bad' } }

      it 'records a postal error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/mailingAddress/zipCode')
      end
    end

    context 'when veteran mailingAddress addressLine1 is too long' do
      let(:form_json) { mutate_form { |h| h['veteran']['mailingAddress']['addressLine1'] = 'x' * 101 } }

      it 'records a length error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/mailingAddress/addressLine1')
      end
    end

    context 'when veteran mailingAddress addressLine2 is not a string' do
      let(:form_json) { mutate_form { |h| h['veteran']['mailingAddress']['addressLine2'] = 12_345 } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran/mailingAddress/addressLine2')
      end
    end

    context 'when serviceBranch is not in the allowed list' do
      let(:form_json) do
        mutate_form do |h|
          h['militaryHistory']['periodsOfService'][0]['serviceBranch'] = 'Not A Real Branch'
        end
      end

      it 'records an error under periodsOfService' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0/serviceBranch')
      end
    end

    context 'when militaryHistory status is not a known value' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['status'] = 'UNKNOWN' } }

      it 'records a status error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/status')
      end
    end

    context 'when militaryHistory status is not a string' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['status'] = true } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/status')
      end
    end

    context 'when a period is not an object' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'] = ['x'] } }

      it 'records an error on the period index' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0')
      end
    end

    context 'when serviceBranch is blank' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'][0]['serviceBranch'] = '' } }

      it 'records a required error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0/serviceBranch')
      end
    end

    context 'when serviceBranch is not a string' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'][0]['serviceBranch'] = 1 } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0/serviceBranch')
      end
    end

    context 'when period dateRange is missing' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'][0].delete('dateRange') } }

      it 'records a dateRange error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0/dateRange')
      end
    end

    context 'when period dateRange from is invalid' do
      let(:form_json) do
        mutate_form do |h|
          h['militaryHistory']['periodsOfService'][0]['dateRange']['from'] = 'not-a-date'
        end
      end

      it 'records a from date error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0/dateRange/from')
        expect(error_messages(claim, '/militaryHistory/periodsOfService/0/dateRange/from'))
          .to include(described_class::COE_DATE_RANGE_STRING_FORMAT_MESSAGE)
      end
    end

    context 'when period dateRange from is wrong type' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'][0]['dateRange']['from'] = 123 } }

      it 'records only a type error for from' do
        claim.validate
        messages = error_messages(claim, '/militaryHistory/periodsOfService/0/dateRange/from')
        expect(messages).to include('must be a string')
        expect(messages).not_to include(described_class::COE_DATE_RANGE_STRING_FORMAT_MESSAGE)
      end
    end

    context 'when period dateRange to is wrong type' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'][0]['dateRange']['to'] = 123 } }

      it 'records a to date type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0/dateRange/to')
      end
    end

    context 'when period dateRange to is invalid string' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'][0]['dateRange']['to'] = 'bogus' } }

      it 'records a to date error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService/0/dateRange/to')
        expect(error_messages(claim, '/militaryHistory/periodsOfService/0/dateRange/to'))
          .to include(described_class::COE_DATE_RANGE_STRING_FORMAT_MESSAGE)
      end
    end

    context 'when period dateRange to is before from' do
      let(:form_json) do
        mutate_form do |h|
          h['militaryHistory']['periodsOfService'][0]['dateRange']['from'] = '2005-01-01T00:00:00.000Z'
          h['militaryHistory']['periodsOfService'][0]['dateRange']['to'] = '2000-01-01T00:00:00.000Z'
        end
      end

      it 'records an ordering error on to' do
        claim.validate
        expect(error_messages(claim, '/militaryHistory/periodsOfService/0/dateRange/to'))
          .to include('must be on or after from')
      end
    end

    context 'when loanHistory hadPriorLoans is missing' do
      let(:form_json) { mutate_form { |h| h['loanHistory'] = h['loanHistory'].except('hadPriorLoans') } }

      it 'records an error on loanHistory hadPriorLoans' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/hadPriorLoans')
      end
    end

    context 'when loanHistory hadPriorLoans is not boolean-like' do
      let(:form_json) { mutate_form { |h| h['loanHistory']['hadPriorLoans'] = 'maybe' } }

      it 'records a hadPriorLoans error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/hadPriorLoans')
      end
    end

    context 'when loanHistory relevantPriorLoans is not an array' do
      let(:form_json) { mutate_form { |h| h['loanHistory']['relevantPriorLoans'] = {} } }

      it 'records an error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans')
      end
    end

    context 'when a prior loan is not an object' do
      let(:form_json) { form_with_prior_loans([1]) }

      it 'records an error on the loan index' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0')
      end
    end

    context 'when prior loan vaLoanNumber is omitted' do
      let(:form_json) { mutate_prior_loan { |l| l.delete('vaLoanNumber') } }

      it 'does not require vaLoanNumber' do
        expect(claim.validate).to be true
        expect(error_attributes(claim)).not_to include('/loanHistory/relevantPriorLoans/0/vaLoanNumber')
      end
    end

    context 'when prior loan vaLoanNumber is not 12 digits' do
      let(:form_json) { mutate_prior_loan { |l| l['vaLoanNumber'] = '1234567890' } }

      it 'records a vaLoanNumber format error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/vaLoanNumber')
      end
    end

    context 'when prior loan vaLoanNumber is numeric 12 digits' do
      let(:form_json) { mutate_prior_loan { |l| l['vaLoanNumber'] = 123_456_789_012 } }

      it 'passes number type' do
        expect(claim.validate).to be true
        expect(error_attributes(claim)).not_to include('/loanHistory/relevantPriorLoans/0/vaLoanNumber')
      end
    end

    context 'when prior loan propertyAddress is missing' do
      let(:form_json) { mutate_prior_loan { |l| l.delete('propertyAddress') } }

      it 'records a propertyAddress error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress')
      end
    end

    context 'when prior loan propertyAddress is not an object' do
      let(:form_json) { mutate_prior_loan { |l| l['propertyAddress'] = 'nope' } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress')
      end
    end

    context 'when prior loan property postalCode is invalid' do
      let(:form_json) { mutate_prior_loan { |l| l['propertyAddress']['postalCode'] = 'bad' } }

      it 'records a postalCode error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress/postalCode')
      end
    end

    context 'when prior loan street2 is not a string' do
      let(:form_json) { mutate_prior_loan { |l| l['propertyAddress']['street2'] = 99 } }

      it 'records a street2 type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress/street2')
      end
    end

    context 'when prior loan property state is invalid' do
      let(:form_json) { mutate_prior_loan { |l| l['propertyAddress']['state'] = 'ZZ' } }

      it 'records a state error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress/state')
      end
    end

    context 'when prior loan street1 is too long' do
      let(:form_json) { mutate_prior_loan { |l| l['propertyAddress']['street1'] = 'x' * 51 } }

      it 'records a length error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress/street1')
      end
    end

    context 'when prior loan city is too long' do
      let(:form_json) { mutate_prior_loan { |l| l['propertyAddress']['city'] = 'x' * 52 } }

      it 'records a length error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress/city')
      end
    end

    context 'when prior loan loanAmount is wrong type' do
      let(:form_json) { mutate_prior_loan { |l| l['loanAmount'] = [] } }

      it 'records a loanAmount error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/loanAmount')
      end
    end

    context 'when naturalDisaster affected is true but dateOfLoss is missing' do
      let(:form_json) { mutate_prior_loan { |l| l['naturalDisaster'] = { 'affected' => 'true' } } }

      it 'records a dateOfLoss error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/naturalDisaster/dateOfLoss')
      end
    end

    context 'when files2 is not an array' do
      let(:form_json) { mutate_form { |h| h['files2'] = {} } }

      it 'records an error' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2')
      end
    end

    context 'when a file2 entry is not an object' do
      let(:form_json) { mutate_form { |h| h['files2'] = [1] } }

      it 'records an error on the file index' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2/0')
      end
    end

    context 'when file2 confirmationCode is missing' do
      let(:form_json) { mutate_form { |h| h['files2'] = [{ 'type' => 'image/jpeg' }] } }

      it 'records a confirmationCode error' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2/0/confirmationCode')
      end
    end

    context 'when file2 confirmationCode is not a string' do
      let(:form_json) do
        mutate_form do |h|
          h['files2'] = [{ 'confirmationCode' => 1, 'type' => 'image/jpeg' }]
        end
      end

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2/0/confirmationCode')
      end
    end

    context 'when file2 type is not a valid MIME string' do
      let(:form_json) do
        mutate_form do |h|
          h['files2'] = [{ 'confirmationCode' => 'ok', 'type' => 'not-a-mime' }]
        end
      end

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2/0/type')
      end
    end

    context 'when file2 name is present but not a string' do
      let(:form_json) do
        mutate_form do |h|
          h['files2'] = [{ 'confirmationCode' => 'ok', 'type' => 'image/jpeg', 'name' => 1 }]
        end
      end

      it 'records a name error' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2/0/name')
      end
    end

    context 'when file2 size is present but not an integer' do
      let(:form_json) do
        mutate_form do |h|
          h['files2'] = [{ 'confirmationCode' => 'ok', 'type' => 'image/jpeg', 'size' => '12' }]
        end
      end

      it 'records a size error' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2/0/size')
      end
    end

    context 'when file2 additionalData is not an object' do
      let(:form_json) do
        mutate_form do |h|
          h['files2'] = [{ 'confirmationCode' => 'ok', 'type' => 'image/jpeg', 'additionalData' => 'x' }]
        end
      end

      it 'records an additionalData error' do
        claim.validate
        expect(error_attributes(claim)).to include('/files2/0/additionalData')
      end
    end

    context 'when loanHistory certificateUse is invalid' do
      let(:form_json) { mutate_form { |h| h['loanHistory']['certificateUse'] = 'INVALID' } }

      it 'records an error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/certificateUse')
      end
    end
  end

  describe 'COE v3 field validation' do
    subject(:claim) { described_class.new(form: form_json) }

    let(:form_json) { valid_v3_form_hash.to_json }

    def mutate_v3_form
      h = valid_v3_form_hash.deep_dup
      yield h
      h.to_json
    end

    context 'with a complete valid v3 payload' do
      it 'passes validation' do
        expect(claim.validate).to be true
        expect(claim.errors).to be_empty
      end
    end

    context 'when status is ADSM and preDischargeClaim is missing' do
      let(:form_json) { mutate_v3_form { |h| h['militaryHistory'].delete('preDischargeClaim') } }

      it 'records a preDischargeClaim required error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/preDischargeClaim')
      end
    end

    context 'when status is ADSM and purpleHeartRecipient is missing' do
      let(:form_json) { mutate_v3_form { |h| h['militaryHistory'].delete('purpleHeartRecipient') } }

      it 'records a purpleHeartRecipient required error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/purpleHeartRecipient')
      end
    end

    context 'when preDischargeClaim is not boolean-like' do
      let(:form_json) { mutate_v3_form { |h| h['militaryHistory']['preDischargeClaim'] = 'maybe' } }

      it 'records a preDischargeClaim error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/preDischargeClaim')
      end
    end

    context 'when status is not ADSM on v3' do
      let(:form_json) do
        mutate_v3_form do |h|
          h['militaryHistory']['status'] = 'VETERAN'
          h['militaryHistory'].delete('preDischargeClaim')
          h['militaryHistory'].delete('purpleHeartRecipient')
        end
      end

      it 'does not require preDischargeClaim or purpleHeartRecipient' do
        expect(claim.validate).to be true
        expect(error_attributes(claim)).not_to include('/militaryHistory/preDischargeClaim')
        expect(error_attributes(claim)).not_to include('/militaryHistory/purpleHeartRecipient')
      end
    end

    context 'when prior loan loanDate is missing' do
      let(:form_json) do
        mutate_v3_form { |h| h['loanHistory']['relevantPriorLoans'][0].delete('loanDate') }
      end

      it 'does not require loanDate' do
        expect(claim.validate).to be true
        expect(error_attributes(claim)).not_to include('/loanHistory/relevantPriorLoans/0/loanDate')
      end
    end

    context 'when prior loan entitlementRestoration is missing' do
      let(:form_json) do
        mutate_v3_form { |h| h['loanHistory']['relevantPriorLoans'][0].delete('entitlementRestoration') }
      end

      it 'records an entitlementRestoration error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/entitlementRestoration')
      end
    end

    context 'when prior loan propertyAddress is missing' do
      let(:form_json) { mutate_v3_form { |h| h['loanHistory']['relevantPriorLoans'][0].delete('propertyAddress') } }

      it 'records a propertyAddress required error' do
        claim.validate
        expect(error_attributes(claim)).to include('/loanHistory/relevantPriorLoans/0/propertyAddress')
      end
    end

    context 'when top-level loanHistory entitlementRestoration is missing' do
      let(:form_json) { mutate_v3_form { |h| h['loanHistory'].delete('entitlementRestoration') } }

      it 'does not require top-level entitlementRestoration' do
        expect(claim.validate).to be true
        expect(error_attributes(claim)).not_to include('/loanHistory/entitlementRestoration')
      end
    end
  end
end
