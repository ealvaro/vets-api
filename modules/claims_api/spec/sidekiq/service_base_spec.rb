# frozen_string_literal: true

require 'rails_helper'
require_relative '../rails_helper'
require_relative '../support/form_526_fixture_helper'

RSpec.describe ClaimsApi::ServiceBase do
  let(:user) { create(:user, :loa3) }

  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end

  let(:claim_date) { (Time.zone.today - 1.day).to_s }
  let(:anticipated_separation_date) { 2.days.from_now.strftime('%m-%d-%Y') }

  let(:ews) { create(:evidence_waiver_submission, :with_full_headers_tamara) }
  let(:errored_ews) { create(:evidence_waiver_submission, :with_full_headers_tamara, status: 'errored') }

  let(:form_data) do
    temp = Form526FixtureHelper.new.data
    attributes = temp['data']['attributes']
    attributes['claimDate'] = claim_date
    attributes['serviceInformation']['federalActivation']['anticipatedSeparationDate'] = anticipated_separation_date

    temp.to_json
  end

  let(:claim) do
    claim = create(:auto_established_claim)
    claim.auth_headers = auth_headers
    claim.save
    claim
  end

  let(:poa) do
    poa = create(:power_of_attorney)
    poa.auth_headers = auth_headers
    poa.status = ClaimsApi::PowerOfAttorney::PENDING
    poa.save
    poa
  end

  let(:process) do
    process = ClaimsApi::Process.create!(
      processable: poa,
      step_type: 'PDF_SUBMISSION',
      step_status: 'IN_PROGRESS'
    )
    process
  end

  let(:service) { described_class.new }

  describe '#set_established_state_on_claim' do
    it 'updates claim status as ESTABLISHED' do
      service.send(:set_established_state_on_claim, claim)
      claim.reload
      expect(claim.status).to eq('established')
      expect(claim.evss_response).to be_nil
    end
  end

  describe '#set_pending_state_on_claim' do
    it 'updates claim status as PENDING' do
      service.send(:set_pending_state_on_claim, claim)
      claim.reload
      expect(claim.status).to eq('pending')
    end
  end

  describe '#set_state_for_submission' do
    it 'updates claim status as ERRORED' do
      service.send(:set_state_for_submission, claim, 'errored')
      claim.reload
      expect(claim.status).to eq('errored')
    end

    it 'updates EWS status as ERRORED' do
      service.send(:set_state_for_submission, ews, 'errored')
      ews.reload
      expect(ews.status).to eq('errored')
    end

    it 'updates EWS status as PENDING' do
      service.send(:set_state_for_submission, errored_ews, 'pending')
      errored_ews.reload
      expect(errored_ews.status).to eq('pending')
    end
  end

  describe '#preserve_original_form_data' do
    it 'preserves the form data as expected' do
      preserved_form_data = service.send(:preserve_original_form_data, claim.form_data)
      claim.reload
      expect(claim.form_data).to eq(preserved_form_data)
    end
  end

  describe '#set_errored_state_on_claim' do
    it 'updates claim status as ERRORED with error details' do
      service.send(:set_errored_state_on_claim, claim)
      claim.reload
      expect(claim.status).to eq('errored')
    end
  end

  describe '#save_auto_claim!' do
    it 'saves claim with the validation_method property of v2' do
      service.send(:save_auto_claim!, claim, claim.status)
      expect(claim.validation_method).to eq('v2')
    end
  end

  describe '#allow_poa_access?' do
    context 'denies eFolder access' do
      it 'if recordConsent is set to false' do
        poa.form_data = poa.form_data.merge('recordConsent' => false)
        poa.save

        res = service.send(:allow_poa_access?, poa_form_data: poa.form_data)
        expect(res).to be(false)
      end

      it 'if recordConsent is not present' do
        poa.save

        res = service.send(:allow_poa_access?, poa_form_data: poa.form_data)
        expect(res).to be(false)
      end

      it 'if consentLimits are present' do
        poa.form_data = poa.form_data.merge('recordConsent' => true)
        poa.form_data = poa.form_data.merge('consentLimits' => ['HIV'])
        poa.save

        res = service.send(:allow_poa_access?, poa_form_data: poa.form_data)
        expect(res).to be(false)
      end
    end

    context 'allows eFolder access' do
      it 'if recordConsent is set to true' do
        poa.form_data = poa.form_data.merge('recordConsent' => true)
        poa.save

        res = service.send(:allow_poa_access?, poa_form_data: poa.form_data)
        expect(res).to be(true)
      end
    end
  end

  describe '#will_retry?' do
    def backend_error_with(body)
      Common::Exceptions::BackendServiceException.new(body.first[:key], {}, nil, body)
    end

    context 'when claim has an evss response key' do
      it 'retries for keys not in the no-retry list' do
        body = [{ key: 'header.va_eauth_birlsfilenumber', severity: 'ERROR', text: 'Size must be between 8 and 9' }]
        claim.evss_response = body
        claim.save!

        expect(service.send(:will_retry?, claim, backend_error_with(body))).to be(true)
      end

      it 'does not retry for form526.InProcess' do
        body = [{ key: 'form526.InProcess', severity: 'FATAL', text: 'Form 526 is already in-process' }]
        claim.evss_response = body
        claim.save!

        expect(service.send(:will_retry?, claim, backend_error_with(body))).to be(false)
      end

      it 'does not retry for form526.submit.noRetryError' do
        body = [{ key: 'form526.submit.noRetryError', severity: 'FATAL',
                  text: 'Claim could not be established. Retries will fail.' }]
        claim.evss_response = body
        claim.save!

        expect(service.send(:will_retry?, claim, backend_error_with(body))).to be(false)
      end
    end

    context 'when claim has no evss response key' do
      before do
        claim.evss_response = nil
        claim.save!
      end

      it 'uses original body keys to block retries for no-retry error codes' do
        error = Common::Exceptions::BackendServiceException.new(
          'form526.InProcess', {}, nil, { key: 'form526.InProcess', text: 'already in process' }
        )

        expect(service.send(:will_retry?, claim, error)).to be(false)
      end

      it 'retries when neither evss response nor original body key is present' do
        error = RuntimeError.new('transient upstream issue')

        expect(service.send(:will_retry?, claim, error)).to be(true)
      end
    end
  end

  describe '#log_job_progress' do
    let(:message) { 'PDF mapper succeeded' }

    it 'logs job progress' do
      expect(ClaimsApi::Logger).to receive(:log).with('claims_api_sidekiq_service_base', claim_id: claim.id, message:)

      service.send(:log_job_progress, claim.id, message)
    end

    it 'logs job progress with transaction_id when provided' do
      transaction_id = '00000000-0000-0000-000000000000'
      expect(ClaimsApi::Logger).to receive(:log).with('claims_api_sidekiq_service_base', claim_id: claim.id, message:,
                                                                                         transaction_id:)

      service.send(:log_job_progress, claim.id, message, transaction_id)
    end
  end

  describe '#form_logger_consent_detail' do
    let(:poa_code) { '065' }

    it 'does not mention consentLimits in the log output if the array is empty' do
      poa = OpenStruct.new(form_data: { 'recordConsent' => true, 'consentLimits' => [] })

      detail = service.send(:form_logger_consent_detail, poa, poa_code)

      expect(detail).to eq("Updating Access. recordConsent: true for representative #{poa_code}")
    end

    it 'does not mention consentLimits in the log output when no consentLimit key is sent' do
      poa = OpenStruct.new(form_data: { 'recordConsent' => true })

      detail = service.send(:form_logger_consent_detail, poa, poa_code)

      expect(detail).to eq("Updating Access. recordConsent: true for representative #{poa_code}")
    end

    it 'mentions consentLimits in the log output if the array has any values' do
      poa = OpenStruct.new(form_data: { 'recordConsent' => true, 'consentLimits' => ['DRUG_ABUSE'] })

      detail = service.send(:form_logger_consent_detail, poa, poa_code)

      expect(detail).to eq(
        "Updating Access. recordConsent: true, consentLimits included for representative #{poa_code}"
      )
    end
  end

  describe '.sidekiq_retries_exhausted' do
    it 'marks claim as errored' do
      msg = {
        'args' => [claim.id],
        'class' => 'ClaimsApi::V1::DisabilityCompensationPdfGenerator',
        'error_message' => 'There has been an error'
      }
      claim_record = instance_double(ClaimsApi::AutoEstablishedClaim)

      allow(ClaimsApi::AutoEstablishedClaim).to receive(:find).with(claim.id).and_return(claim_record)
      expect(claim_record).to receive(:status=).with(ClaimsApi::AutoEstablishedClaim::ERRORED)
      expect(claim_record).to receive(:evss_response=).with(msg['error_message'])
      expect(claim_record).to receive(:save!)

      described_class.within_sidekiq_retries_exhausted_block(msg) do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'claims_api_retries_exhausted',
          record_id: claim.id,
          message: "Job retries exhausted for #{msg['class']}",
          error: msg['error_message']
        )
      end
    end
  end

  describe '#set_evss_response' do
    it 'replaces existing evss_response errors instead of appending' do
      claim.evss_response = ['stale error']
      claim.save!

      service.send(:set_evss_response, claim, StandardError.new('fresh error'))

      claim.reload
      expect(claim.evss_response).to eq([{ 'detail' => 'fresh error' }])
    end

    it 'stores original_body array errors as-is' do
      backend_error = Common::Exceptions::BackendServiceException.new(
        'pdf.error',
        {},
        500,
        [{ 'detail' => 'service failure' }]
      )

      service.send(:set_evss_response, claim, backend_error)

      claim.reload
      expect(claim.evss_response).to eq([{ 'detail' => 'service failure' }])
    end

    it 'stores original_body hash errors as a single array element' do
      backend_error = Common::Exceptions::BackendServiceException.new(
        'pdf.error',
        {},
        500,
        { 'detail' => 'single error payload' }
      )

      service.send(:set_evss_response, claim, backend_error)

      claim.reload
      expect(claim.evss_response).to eq([{ 'detail' => 'single error payload' }])
    end

    it 'unwraps nested errors payloads from original_body hash' do
      error_detail = 'Exactly one identifier, fileNumber or participantId, must be set.'
      backend_error = Common::Exceptions::BackendServiceException.new(
        'pdf.error',
        {},
        400,
        {
          'errors' => [
            {
              'detail' => error_detail,
              'status' => 400,
              'title' => 'Bad Request'
            }
          ]
        }
      )

      service.send(:set_evss_response, claim, backend_error)

      claim.reload
      expect(claim.evss_response).to eq([
                                          {
                                            'detail' => error_detail,
                                            'status' => 400,
                                            'title' => 'Bad Request'
                                          }
                                        ])
    end

    it 'stores a standard error message as a hash with detail key' do
      service.send(:set_evss_response, claim, StandardError.new('Unexpected error occurred'))

      claim.reload
      expect(claim.evss_response).to eq([{ 'detail' => 'Unexpected error occurred' }])
    end

    it 'stores errors from objects exposing an errors array' do
      error = double(:error, errors: [{ 'detail' => 'errors accessor payload' }])

      service.send(:set_evss_response, claim, error)

      claim.reload
      expect(claim.evss_response).to eq([{ 'detail' => 'errors accessor payload' }])
    end
  end

  describe '#normalize_error_message' do
    it 'wraps a plain string error in a hash with a detail key' do
      error = StandardError.new('something went wrong')
      result = service.send(:normalize_error_message, error)

      expect(result).to eq([{ 'detail' => 'something went wrong' }])
    end

    it 'passes through a hash error without modification' do
      error = double(:error, original_body: { 'detail' => 'already structured' })
      result = service.send(:normalize_error_message, error)

      expect(result).to eq([{ 'detail' => 'already structured' }])
    end

    it 'compacts nil messages out of the result' do
      error = double(:error, original_body: nil)
      result = service.send(:normalize_error_message, error)

      expect(result).to eq([])
    end
  end

  describe '#set_vbms_error_message' do
    it 'persists the extracted message to the poa record' do
      error = RuntimeError.new('VBMS unavailable')

      service.send(:set_vbms_error_message, poa, error)
      poa.reload

      expect(poa.vbms_error_message).to eq('VBMS unavailable')
    end
  end

  describe 'error extraction helpers' do
    let(:empty_error) { OpenStruct.new }

    describe '#get_error_message' do
      it 'returns an original_body payload when available' do
        error = double(:error, original_body: { detail: 'upstream payload' })

        expect(service.send(:get_error_message, error)).to eq({ detail: 'upstream payload' })
      end

      it 'returns a message payload when available' do
        error = StandardError.new('plain error message')

        expect(service.send(:get_error_message, error)).to eq('plain error message')
      end

      it 'returns an errors payload when available' do
        error = OpenStruct.new(errors: [{ detail: 'bad data' }])

        expect(service.send(:get_error_message, error)).to eq([{ detail: 'bad data' }])
      end

      it 'returns a detailed_message payload when available' do
        error = OpenStruct.new(detailed_message: 'details from upstream service')

        expect(service.send(:get_error_message, error)).to eq('details from upstream service')
      end

      it 'returns the original error object as a fallback' do
        expect(service.send(:get_error_message, empty_error)).to eq(empty_error)
      end
    end

    describe '#get_error_status_code' do
      it 'returns a fallback message when status code is unavailable' do
        expect(service.send(:get_error_status_code, empty_error)).to eq("No status code for error: #{empty_error}")
      end
    end

    describe '#get_error_text' do
      it 'returns the original value when error_message is a string' do
        expect(service.send(:get_error_text, 'plain text error')).to eq('plain text error')
      end

      it 'prefers nested messages text when available' do
        error_message = {
          messages: [{ text: 'message list text' }],
          text: 'top-level text',
          message: 'top-level message',
          detail: 'top-level detail'
        }

        expect(service.send(:get_error_text, error_message)).to eq('message list text')
      end

      it 'falls back to :text when nested messages text is unavailable' do
        expect(service.send(:get_error_text, { text: 'fallback text' })).to eq('fallback text')
      end

      it 'falls back to :message when nested messages text and :text are unavailable' do
        expect(service.send(:get_error_text, { message: 'fallback message' })).to eq('fallback message')
      end

      it 'falls back to :detail when nested messages text, :text, and :message are unavailable' do
        expect(service.send(:get_error_text, { detail: 'fallback detail' })).to eq('fallback detail')
      end
    end

    describe '#get_original_status_code' do
      it 'returns an empty string when original status is unavailable' do
        expect(service.send(:get_original_status_code, empty_error)).to eq('')
      end
    end
  end

  describe '#established_state_value' do
    it 'returns the established state constant' do
      expect(service.send(:established_state_value)).to eq(ClaimsApi::AutoEstablishedClaim::ESTABLISHED)
    end
  end

  describe '#veteran_file_number' do
    it 'returns va_eauth_birlsfilenumber from auth headers' do
      expect(service.send(:veteran_file_number, claim)).to eq(claim.auth_headers['va_eauth_birlsfilenumber'])
    end
  end

  describe '#save_poa_errored_state' do
    it 'sets the poa status to errored and persists' do
      service.send(:save_poa_errored_state, poa)
      poa.reload

      expect(poa.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
    end
  end

  describe '#vanotify?' do
    let(:rep_id) { '1234' }
    let(:notification_key) { ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController::VA_NOTIFY_KEY }

    context 'when the VA notify feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_poa_va_notify).and_return(true)
      end

      it 'returns true when feature, header key, and representative all exist' do
        create(:representative, representative_id: rep_id)

        expect(service.send(:vanotify?, { notification_key => 'abc123' }, rep_id)).to be(true)
      end

      it 'returns false when the VA notify key is missing from auth headers' do
        create(:representative, representative_id: rep_id)

        expect(service.send(:vanotify?, { 'unrelated_header' => 'abc123' }, rep_id)).to be(false)
      end

      it 'returns false when no representative exists for the given rep_id' do
        expect(service.send(:vanotify?, { notification_key => 'abc123' }, rep_id)).to be(false)
      end
    end

    context 'when the VA notify feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_v2_poa_va_notify).and_return(false)
      end

      it 'returns false when the feature flag is disabled' do
        create(:representative, representative_id: rep_id)

        expect(service.send(:vanotify?, { notification_key => 'abc123' }, rep_id)).to be(false)
      end
    end
  end

  describe '#rescue_file_not_found' do
    it 'updates the Process when called' do
      expect(process.step_status).to eq('IN_PROGRESS')
      expect(process.error_messages).to eq([])

      service.send(:rescue_file_not_found, poa, process)
      process.reload

      expect(process.step_status).to eq('FAILED')
      expect(process.error_messages&.first&.[]('detail')).to eq(
        described_class::FILE_NOT_FOUND_ERROR_MESSAGE
      )
    end

    it 'handles the error without a process' do
      service.send(:rescue_file_not_found, poa)
      poa.reload

      expect(poa.status).to eq('errored')
      expect(poa.vbms_error_message).to eq(
        described_class::FILE_NOT_FOUND_ERROR_MESSAGE
      )
    end
  end

  describe 'retries exhausted class allowlist' do
    it 'includes all three allowlisted classes with corrected names' do
      expect(described_class::RETRIES_EXHAUSTED_CLAIM_CLASSES).to contain_exactly(
        'ClaimsApi::V1::DisabilityCompensationPdfGenerator',
        'ClaimsApi::V1::Form526EstablishmentUpload',
        'ClaimsApi::DisabilityCompensationBenefitsDocumentsUploader'
      )
    end
  end
end
