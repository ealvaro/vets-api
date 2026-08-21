# frozen_string_literal: true

require 'rails_helper'
require 'pega_api/client'

RSpec.describe 'IVC CHAMPVA Integration Failure Scenarios', type: :request do
  let(:user) { create(:user, :loa3) }
  let(:simple_form_data) do
    {
      'form_number' => '10-10D',
      'certifier_role' => 'applicant',
      'primary_contact_info' => {
        'name' => { 'first' => 'Test', 'last' => 'User' },
        'email' => 'test@example.com'
      },
      'veteran' => {
        'full_name' => { 'first' => 'Veteran', 'last' => 'Name' },
        'ssn_or_tin' => '123456789',
        'date_of_birth' => '1980-01-01'
      },
      'applicants' => [
        {
          'applicant_name' => { 'first' => 'Applicant', 'last' => 'Name' },
          'applicant_ssn' => '987654321',
          'applicant_dob' => '1985-01-01',
          'applicant_relationship_to_sponsor' => 'spouse'
        }
      ],
      'certification' => {
        'first_name' => 'Test',
        'last_name' => 'User',
        'date' => '2024-01-01'
      },
      'statement_of_truth_signature' => 'Test User'
    }
  end

  before do
    sign_in(user)
    # Mock AWS to avoid real S3 calls
    Aws.config.update(stub_responses: true)

    # Default all Flipper flags to false, then override specific ones in contexts
    allow(Flipper).to receive(:enabled?).and_return(false)

    # Ensure we're in non-production environment for VES integration
    allow(Settings).to receive(:vsp_environment).and_return('staging')

    # Mock VES data validation to bypass form validation errors
    ves_request = instance_double(IvcChampva::VesRequest,
                                  transaction_uuid: 'test-uuid',
                                  application_uuid: 'app-uuid',
                                  form_type: 'vha_10_10d',
                                  form_1010d?: true,
                                  form_1010dx?: false,
                                  form_7959c?: false,
                                  subforms?: false,
                                  to_json: '{"test": "data"}')
    allow(ves_request).to receive(:transaction_uuid=)
    allow(IvcChampva::VesDataFormatter).to receive(:format_for_request)
      .and_return(ves_request)

    # Mock PDF generation and stamping to avoid file system dependencies
    allow(IvcChampva::PdfFiller).to receive(:new).and_return(
      instance_double(IvcChampva::PdfFiller, generate: '/tmp/test.pdf')
    )
    allow(IvcChampva::PdfStamper).to receive(:stamp_pdf).and_return(true)

    # Mock S3 operations to return success by default
    allow_any_instance_of(IvcChampva::S3).to receive(:put_object)
      .and_return({ success: true, etag: 'test-etag' })
  end

  describe 'VES Integration Failure Scenarios' do
    context 'when VES API fails' do
      before do
        # Mock VES to fail with any error (connection, HTTP, timeout, etc.)
        stub_request(:post, %r{.*/ves-vfmp-app-svc/champva-applications})
          .to_raise(Faraday::ConnectionFailed.new('Connection refused'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs VES error but allows form submission to succeed (graceful degradation)' do
        post '/ivc_champva/v1/forms', params: simple_form_data

        # Verify the VES request was attempted and failed (may retry once)
        expect(WebMock).to have_requested(:post, %r{.*/ves-vfmp-app-svc/champva-applications}).at_least_once

        # Verify VES error was logged (retry mechanism logs the error with exception object)
        expect(Rails.logger).to have_received(:error)
          .with(a_string_matching(/VES Submission: Retry attempt.*failed/), anything).at_least(:once)

        # Verify form submission still succeeded despite VES failure
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_a(Hash)
      end
    end

    context 'when VES API returns HTTP error' do
      before do
        stub_request(:post, %r{.*/ves-vfmp-app-svc/champva-applications})
          .to_return(status: 500, body: 'Internal Server Error')
        allow(Rails.logger).to receive(:error)
      end

      it 'handles VES HTTP errors gracefully' do
        post '/ivc_champva/v1/forms', params: simple_form_data

        # Verify the VES request was attempted and failed (may retry once)
        expect(WebMock).to have_requested(:post, %r{.*/ves-vfmp-app-svc/champva-applications}).at_least_once

        # Verify VES error was logged (retry mechanism logs the error with exception object)
        expect(Rails.logger).to have_received(:error)
          .with(a_string_matching(/VES Submission: Retry attempt.*failed/), anything)
          .at_least(:once)

        # Form submission should still succeed despite VES failure
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_a(Hash)
      end
    end
  end

  describe 'Pega Infrastructure Failure Scenarios' do
    # NOTE: Pega integration is asynchronous via S3 pickup, not direct API calls during form submission.
    # These tests cover infrastructure failures that prevent Pega from receiving form data.

    context 'when database insertion fails during form submission' do
      before do
        # Mock database insertion to fail - prevents IvcChampvaForm record creation
        allow(IvcChampvaForm).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(IvcChampvaForm.new))
      end

      it 'returns 500 error when database record creation fails' do
        post '/ivc_champva/v1/forms', params: simple_form_data

        # Database failure prevents form tracking records from being created
        # Impact: No form records in database, no tracking for Pega processing
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body).to have_key('error_message')
        expect(response.parsed_body['error_message']).to match(/An unknown error occurred while uploading document/)
      end
    end

    context 'when S3 upload fails' do
      before do
        # Mock S3 upload to fail - prevents files and metadata from reaching S3 bucket
        allow_any_instance_of(IvcChampva::FileUploader).to receive(:upload)
          .and_return([500, 'S3 connection failed'])
      end

      it 'returns 500 error when S3 upload fails' do
        post '/ivc_champva/v1/forms', params: simple_form_data

        # S3 failure prevents metadata JSON upload that triggers Pega lambda
        # Impact: Pega cannot process form (nothing in S3 bucket to pick up)
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body).to have_key('error_message')
        expect(response.parsed_body['error_message']).to match(/An unknown error occurred while uploading document/)
      end
    end
  end
end
