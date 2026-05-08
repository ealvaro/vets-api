# frozen_string_literal: true

require 'rails_helper'
require 'fes_service/base'

describe ClaimsApi::FesService::Base do
  let(:service) { described_class.new }
  let(:claim) do
    double('claim',
           id: 123,
           transaction_id: 'abc-123-def',
           auth_headers: { 'va_eauth_pid' => '600043201' },
           veteran: double('veteran', participant_id: '600043201'),
           claimant_participant_id: nil)
  end
  let(:invalid_form_data) do
    {
      form526: {
        'veteran' => { 'firstName' => 'John', 'lastName' => 'Doe' },
        'disabilities' => [{ 'name' => 'Hearing Loss' }]
      }
    }
  end
  let(:fes_auth_headers) do
    { 'va_eauth_csid' => 'DSLogon', 'va_eauth_authenticationmethod' => 'DSLogon', 'va_eauth_pnidtype' => 'SSN',
      'va_eauth_assurancelevel' => '3', 'va_eauth_firstName' => 'Pauline', 'va_eauth_lastName' => 'Foster',
      'va_eauth_issueinstant' => '2025-08-19T13:57:05Z', 'va_eauth_dodedipnid' => '1243413229',
      'va_eauth_birlsfilenumber' => '123456', 'va_eauth_pid' => '600049703', 'va_eauth_pnid' => '796330625',
      'va_eauth_birthdate' => '1976-06-09T00:00:00+00:00',
      'va_eauth_authorization' => '{"authorizationResponse":{"status":"VETERAN","idType":"SSN","id":"796330625",' \
                                  '"edi":"1243413229","firstName":"Pauline","lastName":"Foster", ' \
                                  '"birthDate":"1976-06-09T00:00:00+00:00",' \
                                  '"gender":"MALE"}}', 'va_eauth_authenticationauthority' => 'eauth',
      'va_eauth_service_transaction_id' => '00000000-0000-0000-0000-000000000000' }
  end
  let(:min_fes_mapped_data) do
    { data: {
      serviceTransactionId: 'claims-api-6913cb91-f077-4368-baf3-1bb642ffc0dd-1755612075',
      claimantParticipantId: '600049703',
      veteranParticipantId: '600049703',
      form526: {
        serviceInformation: {
          servicePeriods: [{
            serviceBranch: 'Air Force', activeDutyBeginDate: '2015-11-14', activeDutyEndDate: '2018-11-30'
          }]
        },
        veteran: { currentMailingAddress: {
          addressLine1: '1234 Couch Street', country: 'USA', zipFirstFive: '12345',
          addressType: 'DOMESTIC', city: 'Portland', state: 'OR'
        } },
        disabilities: [{ name: 'hearing loss', disabilityActionType: 'NEW',
                         approximateBeginDate: { year: 2017, month: 7 } }],
        claimDate: '2025-08-19'
      }
    } }
  end
  let(:fes_claim) do
    claim = create(:auto_established_claim)
    claim.transaction_id = '00000000-0000-0000-000000000000'
    claim.auth_headers = fes_auth_headers
    claim.save
    claim
  end
  let(:async) { true }
  let(:not_async) { false }

  describe '#validate' do
    context 'successful validation' do
      it 'returns validation success' do
        VCR.use_cassette('/claims_api/fes/validate/success') do
          response = service.validate(fes_claim, min_fes_mapped_data, not_async)

          expect(response[:valid]).to be(true)
          expect(response).to have_key(:success)
        end
      end
    end

    context 'validation with errors' do
      it 'returns a 400' do
        VCR.use_cassette('/claims_api/fes/validate/bad_request') do
          expect do
            service.validate(claim, invalid_form_data, not_async)
          end.to raise_error(
            ClaimsApi::Common::Exceptions::Lighthouse::BackendServiceException
          )
        end
      end
    end

    context 'invalid data values' do
      it 'returns a 400' do
        invalid_data = min_fes_mapped_data
        invalid_data[:data][:form526][:serviceInformation][:servicePeriods][0][:serviceBranch] = 'AIR\n Force'

        VCR.use_cassette('/claims_api/fes/validate/invalid_request') do
          expect { service.validate(claim, invalid_data, not_async) }
            .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::BackendServiceException)
        end
      end
    end
  end

  describe '#sanitize_error_detail_pii' do
    # These tests are based on known FES validation errors
    # that include user data in the error detail.
    # see the lighthouse-form526-establishment-service repository
    # for the Java code that generates these errors and the error
    # messages that may contain PII.
    context 'FES validation errors (with source pointer)' do
      it 'redacts detail for all known FES validation error types' do
        response = { data: { isValid: false, errors: [
          # DisabilitiesValidator.java:260 — disability name format
          { status: '400', title: 'Invalid value name',
            detail: 'The disability name BAD&@$ NAME does not match the expected format',
            source: { pointer: '/data/form526/disabilities/0/name' } },
          # DisabilitiesValidator.java:89 — duplicate disability name
          { status: '400', title: 'Invalid value',
            detail: 'Duplicate disability name found: My back hurts and my name is John Smith',
            source: { pointer: '/data/form526/disabilities/1/name' } },
          # AddressValidator.java:53 — invalid country
          { status: '400', title: 'Invalid country',
            detail: 'Provided country is not valid: United States of America',
            source: { pointer: '/data/form526/veteran/currentMailingAddress/country' } },
          # ServicePeriodsValidator.java:61 — invalid service branch
          { status: '400', title: 'Invalid service period branch name',
            detail: 'Provided service period branch name is not valid: Air Force Reserve',
            source: { pointer: '/data/form526/serviceInformation/servicePeriods/0/serviceBranch' } },
          # ServicePeriodsValidator.java:76-79 — dates out of order
          { status: '400', title: 'Invalid service period duty dates',
            detail: 'Provided service period duty dates are out of order: begin=1988-01-24 end=1988-01-24',
            source: { pointer: '/data/form526/serviceInformation/servicePeriods/2/activeDutyBeginDate' } },
          # ServicePeriodsValidator.java:93 — end date too far in future
          { status: '400', title: 'Invalid end service period duty date',
            detail: 'Provided service period duty end date is more than 180 days in the future: 2028-01-01',
            source: { pointer: '/data/form526/serviceInformation/servicePeriods/0/activeDutyEndDate' } },
          # ServicePeriodsValidator.java:131-133 — start date before 13th birthday
          { status: '400', title: 'Invalid start service period duty start date',
            detail: 'Provided service period duty start date occurs prior to claimants 13th birthday: 1970-01-01',
            source: { pointer: '/data/form526/serviceInformation/servicePeriods/0/activeDutyStartDate' } },
          # DisabilitiesValidator.java:151,157 — classification codes
          { status: '400', title: 'Invalid value',
            detail: 'The disability classification code is not valid: 9999',
            source: { pointer: '/data/form526/disabilities/2/classificationCode' } },
          { status: '400', title: 'Invalid value',
            detail: 'The disability classification code is deactivated: 1234',
            source: { pointer: '/data/form526/disabilities/3/classificationCode' } },
          # DisabilitiesValidator.java:176,182 — diagnostic codes
          { status: '400', title: 'Invalid value',
            detail: 'The disability diagnostic code is not valid: 5678',
            source: { pointer: '/data/form526/disabilities/4/diagnosticCode' } },
          { status: '400', title: 'Invalid value',
            detail: 'The disability diagnostic code is deactivated: 9012',
            source: { pointer: '/data/form526/disabilities/5/diagnosticCode' } },
          # DisabilitiesValidator.java:232 — invalid action type
          { status: '400', title: 'Invalid disability action type',
            detail: 'Unable to validate disability with Action Type INVALID',
            source: { pointer: '/data/form526/disabilities/6/disabilityActionType' } },
          # SeparationLocationsValidator.java:21 — invalid separation location
          { status: '400', title: 'Invalid separation location code',
            detail: 'Provided separation location code is not valid: ZZZZZ',
            source: { pointer: '/data/form526/serviceInformation/separationLocationCode' } },
          # ValidateClaimDateWorkflowStep.java:37 — future claim date
          { status: '400', title: 'Invalid claim date',
            detail: 'Claim date was in the future: 2028-12-25',
            source: { pointer: '/data/form526/claimDate' } },
          # ValidateForwardingAddressWorkflowStep.java:47 — forwarding address
          { status: '400', title: 'Invalid forwarding address',
            detail: 'The ForwardingAddress address validation failed. Address not found in USPS database',
            source: { pointer: '/data/form526/veteran/changeOfAddress' } },
          # ReservesNationalGuardServiceValidator.java — activation/separation dates
          { status: '400', title: 'Invalid value',
            detail: 'Reserves national guard title 10 activation date is in the future: 2028-06-15',
            source: { pointer: '/data/form526/serviceInformation/reservesNationalGuardService/' \
                               'title10Activation/title10ActivationDate' } },
          { status: '400', title: 'Invalid value',
            detail: 'Reserves national guard anticipated separation date must be in the future ' \
                    ' and less than 180 days from today: 2020-01-01',
            source: { pointer: '/data/form526/serviceInformation/reservesNationalGuardService/' \
                               'title10Activation/anticipatedSeparationDate' } },
          { status: '400', title: 'Invalid value',
            detail: 'Reserves national guard title 10 activation date (2015-01-01) is before the earliest ' \
                    'active duty begin date (2016-01-01)',
            source: { pointer: '/data/form526/serviceInformation/reservesNationalGuardService/' \
                               'title10Activation/title10ActivationDate' } },
          # AddressValidator.java:120,134 — beginningDate errors
          { status: '400', title: 'Invalid beginningDate',
            detail: 'BeginningDate cannot be in the past: 2020-01-15',
            source: { pointer: '/data/form526/veteran/changeOfAddress/beginningDate' } },
          { status: '400', title: 'Invalid beginningDate',
            detail: 'BeginningDate cannot be after endingDate: 2026-12-01',
            source: { pointer: '/data/form526/veteran/changeOfAddress/beginningDate' } }
        ] } }

        result = service.send(:sanitize_error_detail_pii, response)

        # Every error with a source pointer should have its detail redacted
        response[:data][:errors].each do |error|
          expect(result).not_to include(error[:detail])
          # All source pointers should be preserved for debugging
          expect(result).to include(error[:source][:pointer])
        end
      end
    end

    context 'Spring @Valid errors (no source pointer, uses instance/diagnostics)' do
      it 'redacts echoed field value in city length error' do
        # WebExceptionHandler.java:370-372 — field = 'rejectedValue': defaultMessage
        response = { errors: [{ detail: "parameter 'form526Request' has 1 errors: " \
                                        '(form526RequestV1.data.form526.veteran.currentMailingAddress.city ' \
                                        "= 'Rolling Hills Estates':  City is longer than 20 characters)",
                                status: 400, title: 'Bad Request',
                                instance: 'abc-123' }] }
        expected = { errors: [{ detail: "parameter 'form526Request' has 1 errors: " \
                                        '(form526RequestV1.data.form526.veteran.currentMailingAddress.city ' \
                                        "= '[REDACTED]':  City is longer than 20 characters)",
                                status: 400, title: 'Bad Request',
                                instance: 'abc-123' }] }
        expect(service.send(:sanitize_error_detail_pii, response)).to eq(expected.to_s)
      end

      it 'redacts multiple echoed field values in multi-error response' do
        # WebExceptionHandler.java:380 — errors joined with " and "
        response = { errors: [{ detail: "parameter 'form526Request' has 2 errors: " \
                                        '(form526RequestV1.data.form526.veteran.currentMailingAddress.city ' \
                                        "= 'Rolling Hills Estates':  City is longer than 20 characters) and " \
                                        '(form526RequestV1.data.form526.veteran.currentMailingAddress.addressLine1 ' \
                                        "= '12345 Very Long Street Name Boulevard Suite 100':  " \
                                        'Address line 1 is longer than 35 characters)',
                                status: 400, title: 'Bad Request',
                                instance: 'def-456' }] }
        expected = { errors: [{ detail: "parameter 'form526Request' has 2 errors: " \
                                        '(form526RequestV1.data.form526.veteran.currentMailingAddress.city ' \
                                        "= '[REDACTED]':  City is longer than 20 characters) and " \
                                        '(form526RequestV1.data.form526.veteran.currentMailingAddress.addressLine1 ' \
                                        "= '[REDACTED]':  " \
                                        'Address line 1 is longer than 35 characters)',
                                status: 400, title: 'Bad Request',
                                instance: 'def-456' }] }
        expect(service.send(:sanitize_error_detail_pii, response)).to eq(expected.to_s)
      end
    end

    context 'safe errors (preserved for debugging)' do
      it 'preserves mailing address validation failed without PII' do
        # ValidationWorkflowExceptions.java:112 — "The " + addrType + " address validation failed."
        response = { errors: [{ detail: 'The MailingAddress address validation failed.',
                                status: 400, title: 'Bad Request',
                                instance: 'abc-123' }] }
        expect(service.send(:sanitize_error_detail_pii, response)).to eq(response.to_s)
      end

      it 'redacts detail for errors with source pointer even when detail has no PII' do
        # All errors with a source pointer get detail redacted uniformly —
        # we cannot reliably distinguish safe vs. unsafe detail content.
        response = { data: { isValid: false, errors: [
          { status: '400', title: 'Invalid disability count',
            detail: 'Must have at least 1 disability',
            source: { pointer: '/data/form526/disabilities' } }
        ] } }
        expected = { data: { isValid: false, errors: [
          { status: '400', title: 'Invalid disability count',
            detail: '[REDACTED]',
            source: { pointer: '/data/form526/disabilities' } }
        ] } }
        expect(service.send(:sanitize_error_detail_pii, response)).to eq(expected.to_s)
      end
    end

    context 'non-hash responses' do
      it 'returns string as-is' do
        expect(service.send(:sanitize_error_detail_pii, 'Some string error message')).to eq('Some string error message')
      end
    end
  end

  describe '#submit' do
    context 'successful submission' do
      it 'returns submission success' do
        VCR.use_cassette('/claims_api/fes/submit/success') do
          response = service.submit(fes_claim, min_fes_mapped_data, not_async)

          expect(response[:claimId]).to eq(600883061) # rubocop:disable Style/NumericLiterals
          expect(response[:requestId]).not_to be_nil
        end
      end
    end

    context 'invalid data values' do
      it 'returns a 400' do
        invalid_data = min_fes_mapped_data
        invalid_data[:data][:form526][:serviceInformation][:servicePeriods][0][:serviceBranch] = 'AIR\n Force'

        VCR.use_cassette('/claims_api/fes/submit/invalid_request') do
          expect { service.submit(claim, invalid_form_data, not_async) }
            .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::BackendServiceException)
        end
      end
    end

    context 'invalid data format' do
      it 'returns a 400' do
        VCR.use_cassette('/claims_api/fes/submit/bad_request') do
          expect { service.submit(claim, invalid_form_data, not_async) }
            .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::BackendServiceException)
        end
      end
    end
  end
end
