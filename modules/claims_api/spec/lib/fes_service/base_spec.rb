# frozen_string_literal: true

require 'rails_helper'
require_relative '../../rails_helper'
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

  before do
    stub_claims_fes_api_auth_token
  end

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

    context 'invalid data values', vcr: '/claims_api/fes/submit/invalid_request' do
      let(:invalid_data) do
        data = min_fes_mapped_data.deep_dup
        data[:data][:form526][:serviceInformation][:servicePeriods][0][:serviceBranch] = 'AIR\n Force'
        data
      end

      it 'returns a 400' do
        expect { service.submit(claim, invalid_data, not_async) }
          .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::BackendServiceException)
      end

      it 'calls pii_redaction on the returned error message' do
        expect(ClaimsApi::PiiRedaction).to receive(:sanitize_error_detail_pii)

        expect { service.submit(claim, invalid_data, not_async) }
          .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::BackendServiceException)
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

  describe '#access_token' do
    context 'when auth token is fetched from service' do
      it 'returns the fetched token' do
        token_value = 'valid_fes_token_12345'
        allow_any_instance_of(ClaimsApi::V2::Form526EstablishmentService::Service)
          .to receive(:get_auth_token).and_return(token_value)

        result = service.send(:access_token)

        expect(result).to eq(token_value)
      end
    end

    context 'when auth token is blank' do
      it 'raises StandardError with FES auth token missing message' do
        allow_any_instance_of(ClaimsApi::V2::Form526EstablishmentService::Service)
          .to receive(:get_auth_token).and_return(nil)

        expect { service.send(:access_token) }
          .to raise_error(StandardError, 'FES auth token missing')
      end
    end

    context 'when mocked is true' do
      it 'returns fake_token without calling auth service' do
        with_settings(Settings.claims_api.fes, mock_claims: true) do
          result = service.send(:access_token)

          expect(result).to eq('fake_token')
        end
      end
    end
  end

  describe 'mocking' do
    context 'when Settings.claims_api.fes.mock_claims is true' do
      it 'returns @auth_headers unchanged, without adding an Authorization header' do
        with_settings(Settings.claims_api.fes, mock_claims: true) do
          service.instance_variable_set(:@auth_headers, fes_auth_headers)

          result = service.send(:headers)

          expect(result).to eq(fes_auth_headers)
          expect(result).not_to have_key(:Authorization)
          expect(result).not_to have_key('Authorization')
        end
      end

      it 'does not call the FES auth token service' do
        with_settings(Settings.claims_api.fes, mock_claims: true) do
          expect_any_instance_of(ClaimsApi::V2::Form526EstablishmentService::Service)
            .not_to receive(:get_auth_token)

          service.instance_variable_set(:@auth_headers, fes_auth_headers)

          service.send(:headers)
        end
      end
    end
  end

  describe '#get_error_message' do
    context 'when error has different response attributes' do
      it 'returns original_body when present' do
        error = double('error', original_body: 'original error body')
        result = service.send(:get_error_message, error)

        expect(result).to eq('original error body')
      end

      it 'returns body when original_body is not present' do
        error = double('error',
                       original_body: nil,
                       body: 'response body content')
        allow(error).to receive(:respond_to?).with(:original_body).and_return(true)
        allow(error).to receive(:respond_to?).with(:body).and_return(true)

        result = service.send(:get_error_message, error)

        expect(result).to eq('response body content')
      end

      it 'returns message when body is not present' do
        error = double('error',
                       original_body: nil,
                       body: nil,
                       message: 'error message text')
        allow(error).to receive(:respond_to?).with(:original_body).and_return(true)
        allow(error).to receive(:respond_to?).with(:body).and_return(true)
        allow(error).to receive(:respond_to?).with(:message).and_return(true)

        result = service.send(:get_error_message, error)

        expect(result).to eq('error message text')
      end

      it 'returns errors when prior attributes are not present' do
        error = double('error',
                       original_body: nil,
                       body: nil,
                       message: nil,
                       errors: %w[error1 error2])
        allow(error).to receive(:respond_to?).with(:original_body).and_return(true)
        allow(error).to receive(:respond_to?).with(:body).and_return(true)
        allow(error).to receive(:respond_to?).with(:message).and_return(true)
        allow(error).to receive(:respond_to?).with(:errors).and_return(true)

        result = service.send(:get_error_message, error)

        expect(result).to eq(%w[error1 error2])
      end

      it 'returns detailed_message when no prior attributes are present' do
        error = double('error',
                       original_body: nil,
                       body: nil,
                       message: nil,
                       errors: nil,
                       detailed_message: 'detailed error info')
        allow(error).to receive(:respond_to?).with(:original_body).and_return(true)
        allow(error).to receive(:respond_to?).with(:body).and_return(true)
        allow(error).to receive(:respond_to?).with(:message).and_return(true)
        allow(error).to receive(:respond_to?).with(:errors).and_return(true)
        allow(error).to receive(:respond_to?).with(:detailed_message).and_return(true)

        result = service.send(:get_error_message, error)

        expect(result).to eq('detailed error info')
      end

      it 'returns formatted message from a real VCR-backed FES submit error' do
        captured_error = nil

        VCR.use_cassette('/claims_api/fes/submit/invalid_request') do
          service.submit(claim, invalid_form_data, not_async)
        rescue ClaimsApi::Common::Exceptions::Lighthouse::BackendServiceException => e
          captured_error = e
        end

        expect(captured_error).to be_present

        result = service.send(:get_error_message, captured_error)

        expect(result).to be_a(String)
        expect(result).to include('The claim could not be established')
        expect(result).to include('Http Message Not Readable (Unrecognized Property)')
      end
    end
  end

  describe '#parse_fes_response' do
    context 'when FES response is not a Hash' do
      it 'raises ParsingError for string response' do
        expect { service.send(:parse_fes_response, '<html>error</html>') }
          .to raise_error(Common::Client::Errors::ParsingError,
                          'FES service returned an unexpected response format')
      end

      it 'raises ParsingError for array response' do
        expect { service.send(:parse_fes_response, %w[error values]) }
          .to raise_error(Common::Client::Errors::ParsingError,
                          'FES service returned an unexpected response format')
      end

      it 'raises ParsingError for nil response' do
        expect { service.send(:parse_fes_response, nil) }
          .to raise_error(Common::Client::Errors::ParsingError,
                          'FES service returned an unexpected response format')
      end
    end

    context 'when FES response is a Hash' do
      it 'returns data key when present' do
        response = { data: { claimId: 123 } }
        result = service.send(:parse_fes_response, response)

        expect(result).to eq({ claimId: 123 })
      end

      it 'returns string data key as fallback' do
        response = { 'data' => { 'claimId' => 456 } }
        result = service.send(:parse_fes_response, response)

        expect(result).to eq({ 'claimId' => 456 })
      end

      it 'returns full response when data key is not present' do
        response = { claimId: 789, status: 'success' }
        result = service.send(:parse_fes_response, response)

        expect(result).to eq(response)
      end
    end
  end
end
