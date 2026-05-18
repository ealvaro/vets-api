# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/pii_redaction'

RSpec.describe ClaimsApi::PiiRedaction do
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

        result = described_class.send(:sanitize_error_detail_pii, response)

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
        expect(described_class.send(:sanitize_error_detail_pii, response)).to eq(expected.to_s)
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
        expect(described_class.send(:sanitize_error_detail_pii, response)).to eq(expected.to_s)
      end
    end

    context 'safe errors (preserved for debugging)' do
      it 'preserves mailing address validation failed without PII' do
        # ValidationWorkflowExceptions.java:112 — "The " + addrType + " address validation failed."
        response = { errors: [{ detail: 'The MailingAddress address validation failed.',
                                status: 400, title: 'Bad Request',
                                instance: 'abc-123' }] }
        expect(described_class.send(:sanitize_error_detail_pii, response)).to eq(response.to_s)
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
        expect(described_class.send(:sanitize_error_detail_pii, response)).to eq(expected.to_s)
      end
    end

    context 'non-hash responses' do
      it 'returns string as-is' do
        expect(described_class.send(:sanitize_error_detail_pii,
                                    'Some string error message')).to eq('Some string error message')
      end
    end
  end
end
