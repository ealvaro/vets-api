# frozen_string_literal: true

require 'rails_helper'
require 'claims_evidence_api/service/files'

RSpec.describe ClaimsEvidence::UploadEvidence do
  subject(:service) { described_class.new(current_user:, upload:, password:) }

  let(:current_user) { create(:user, :loa3, :legacy_icn) }
  let(:password) { nil }
  let(:doc_type_id) { 34 } # Correspondence
  let(:sc_id) { 'SC10879' }
  let(:file) { Rack::Test::UploadedFile.new('spec/fixtures/files/doctors-note.pdf', 'application/pdf') }
  let(:upload) do
    ClaimsEvidence::UploadRequest.new(
      file:, doc_type_id:, sc_id:, file_name: 'doctors-note.pdf', file_size: file.size
    )
  end
  let(:ce_success) { build(:claims_evidence_service_files_response, :success) }
  let(:base_tags) { ClaimsEvidence::Metrics::TAGS }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Common::VirusScan).to receive(:scan).and_return(true)
    allow(Rails).to receive(:cache).and_return(cache)
    allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload).and_return(ce_success)
  end

  describe '#call' do
    it 'returns the uuid pair and the Claims Evidence status for the controller to render' do
      result = service.call

      expect(result.status).to eq(200)
      expect(result.payload).to eq(
        'uuid' => 'c30626c9-954d-4dd1-9f70-1e38756d9d97',
        'currentVersionUuid' => 'c30626c9-954d-4dd1-9f70-1e38756d9d98'
      )
    end

    it 'sets the folder identifier from the user ICN' do
      expect_any_instance_of(ClaimsEvidenceApi::Service::Files)
        .to receive(:folder_identifier=).with("VETERAN:ICN:#{current_user.icn}").and_call_original
      service.call
    end

    it 'sends the provider data Claims Evidence files the document under' do
      expect_any_instance_of(ClaimsEvidenceApi::Service::Files)
        .to receive(:upload)
        .with(anything, provider_data: hash_including(
          contentSource: ClaimsEvidenceApi::CONTENT_SOURCE,
          documentTypeId: doc_type_id
        ))
        .and_return(ce_success)
      service.call
    end

    it 'dates the document in the Claims Evidence timezone rather than UTC' do
      Timecop.freeze(Time.utc(2026, 3, 15, 2, 0, 0)) do
        expect_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload)
          .with(anything, provider_data: hash_including(dateVaReceivedDocument: '2026-03-14'))
          .and_return(ce_success)
        service.call
      end
    end

    it 'stages the file on a relative path inside the scan directory, and cleans it up' do
      staged_path = nil
      allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
        .to receive(:upload) do |_instance, path, **_kwargs|
          staged_path = path
          ce_success
        end

      service.call

      expect(staged_path).to start_with('clamav_tmp/')
      expect(File.exist?(staged_path)).to be(false)
    end

    describe 'releasing the duplicate lock' do
      let(:duplicate_check) do
        instance_double(ClaimsEvidence::DuplicateCheck,
                        presumed_duplicate?: false, acquire_lock: true, release_lock: true)
      end

      before { allow(ClaimsEvidence::DuplicateCheck).to receive(:new).and_return(duplicate_check) }

      it 'releases with retry_blocked false once the row exists to catch repeats' do
        service.call
        expect(duplicate_check).to have_received(:release_lock).with(retry_blocked: false).once
      end

      it 'releases with retry_blocked true when the file never reached Claims Evidence' do
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload).and_raise(build(:claims_evidence_service_files_error, :error))

        expect { service.call }.to raise_error(Common::Client::Errors::ClientError)

        expect(duplicate_check).to have_received(:release_lock).with(retry_blocked: true).once
      end

      it 'holds the lock when the document was filed but no row was written' do
        allow(EvidenceSubmission).to receive(:create!).and_raise(StandardError.new('boom'))

        service.call

        expect(duplicate_check).not_to have_received(:release_lock)
      end
    end

    it 'increments the success counter tagged with documentTypeId and logs the document type name' do
      allow(StatsD).to receive(:increment).and_call_original
      allow(Rails.logger).to receive(:info)

      service.call

      expect(StatsD).to have_received(:increment).with(
        'api.claims_evidence.upload.success', tags: base_tags + ["document_type_id:#{doc_type_id}"]
      )
      expect(Rails.logger).to have_received(:info).with(
        'ClaimsEvidenceController#create upload success', document_type: 'Correspondence'
      )
    end

    describe 'the EvidenceSubmission row' do
      it 'persists a SUCCESS row with caseflow_claim_id and file metadata' do
        expect { service.call }.to change(EvidenceSubmission, :count).by(1)

        es = EvidenceSubmission.last
        expect(es.caseflow_claim_id).to eq(sc_id)
        expect(es.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS])
        expect(es.user_account_id).to eq(current_user.user_account_uuid)
        expect(es.claim_id).to be_nil
        expect(es.file_size).to be > 0
        expect(es.delete_date).to be_within(1.minute).of(60.days.from_now)
        metadata = JSON.parse(es.template_metadata)
        expect(metadata.dig('personalisation', 'file_name')).to eq('doctors-note.pdf')
        expect(metadata.dig('personalisation', 'document_type_id')).to eq(doc_type_id)
        expect(metadata.dig('personalisation', 'document_type')).to eq('Correspondence')
      end
    end

    # The upload is done and the record is saved before this telemetry runs, so a broken
    # metric or log must not fail the call or report it as a failure.
    context 'when the success telemetry itself fails' do
      it 'counts the success once and no failure when the logger raises after the counter' do
        allow(StatsD).to receive(:increment).and_call_original
        allow(Rails.logger).to receive(:info).and_call_original
        allow(Rails.logger).to receive(:info)
          .with('ClaimsEvidenceController#create upload success', any_args)
          .and_raise(StandardError, 'logger down')

        expect(service.call.payload['uuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d97')
        expect(StatsD).to have_received(:increment).with('api.claims_evidence.upload.success', anything)
        expect(StatsD).not_to have_received(:increment).with('api.claims_evidence.upload.failure', anything)
      end

      it 'still returns the result when the counter raises, even though the metric is lost' do
        allow(StatsD).to receive(:increment).and_call_original
        allow(StatsD).to receive(:increment)
          .with('api.claims_evidence.upload.success', anything)
          .and_raise(StandardError, 'statsd down')

        expect(service.call.payload['uuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d97')
        expect(StatsD).not_to have_received(:increment).with('api.claims_evidence.upload.failure', anything)
      end
    end

    context 'when the file is already filed on the claim' do
      before { service.call }

      it 'raises DuplicateUpload tagged detected_by:completed' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { described_class.new(current_user:, upload:, password:).call }
          .to raise_error(described_class::DuplicateUpload)

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['reason:duplicate', 'detected_by:completed', "document_type_id:#{doc_type_id}"]
        )
      end

      it 'does not send the file to Claims Evidence a second time' do
        expect_any_instance_of(ClaimsEvidenceApi::Service::Files).not_to receive(:upload)
        expect { described_class.new(current_user:, upload:, password:).call }
          .to raise_error(described_class::DuplicateUpload)
      end
    end

    # No row was written, so the Redis lock is the only thing that knows the upload happened.
    context 'when a prior attempt filed the document but failed to persist the row' do
      before do
        allow(EvidenceSubmission).to receive(:create!).and_raise(StandardError.new('boom'))
        service.call
      end

      it 'raises DuplicateUpload tagged detected_by:in_flight' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { described_class.new(current_user:, upload:, password:).call }
          .to raise_error(described_class::DuplicateUpload)

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['reason:duplicate', 'detected_by:in_flight', "document_type_id:#{doc_type_id}"]
        )
      end
    end

    context 'when the file contains a virus' do
      before do
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload).and_raise(ClaimsEvidenceApi::Service::Files::VirusFound)
      end

      it 'increments the upload failure counter with reason:virus and re-raises' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(ClaimsEvidenceApi::Service::Files::VirusFound)

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['reason:virus', "document_type_id:#{doc_type_id}"]
        )
      end

      it 'does not persist an EvidenceSubmission' do
        expect { service.call }.to raise_error(ClaimsEvidenceApi::Service::Files::VirusFound)
          .and(not_change(EvidenceSubmission, :count))
      end
    end

    context 'when Claims Evidence rejects the upload' do
      before do
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload).and_raise(build(:claims_evidence_service_files_error, :error))
      end

      it 'increments the upload failure counter tagged with the error class and re-raises' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(Common::Client::Errors::ClientError)

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['error_class:Common::Client::Errors::ClientError',
                             "document_type_id:#{doc_type_id}"]
        )
      end

      it 'releases the lock so the same file can be retried' do
        expect { service.call }.to raise_error(Common::Client::Errors::ClientError)

        allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload).and_return(ce_success)
        expect { described_class.new(current_user:, upload:, password:).call }
          .to change(EvidenceSubmission, :count).by(1)
      end
    end

    context 'when staging the file fails before the Claims Evidence call' do
      before do
        file # build the fixture before stubbing the copy it depends on
        allow(IO).to receive(:copy_stream).and_raise(Errno::ENOSPC)
      end

      it 'never reaches Claims Evidence' do
        expect_any_instance_of(ClaimsEvidenceApi::Service::Files).not_to receive(:upload)
        expect { service.call }.to raise_error(Errno::ENOSPC)
      end

      it 'counts an upload failure tagged with the error class' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(Errno::ENOSPC)

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['error_class:Errno::ENOSPC', "document_type_id:#{doc_type_id}"]
        )
      end
    end

    # A rejected PDF is something the Veteran can fix, and the controller counts it as a
    # validation failure. Counting it here as well would report one rejection twice.
    context 'when the PDF is rejected' do
      let(:rejection) do
        ClaimsEvidence::PdfUnlocker::Rejected.new(reason: 'encrypted_pdf', code: 'DOC_UPLOAD_ENCRYPTED_PDF')
      end

      before do
        allow_any_instance_of(ClaimsEvidence::PdfUnlocker).to receive(:unlock!).and_raise(rejection)
      end

      it 'does not count an upload failure' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(ClaimsEvidence::PdfUnlocker::Rejected)

        expect(StatsD).not_to have_received(:increment).with('api.claims_evidence.upload.failure', anything)
      end
    end

    context 'when persisting the EvidenceSubmission fails' do
      before { allow(EvidenceSubmission).to receive(:create!).and_raise(StandardError.new('boom')) }

      it 'still returns the result because the document is already in the eFolder' do
        expect(service.call.status).to eq(200)
      end

      it 'increments the persistence failure counter tagged with the error class' do
        allow(StatsD).to receive(:increment).and_call_original
        service.call
        expect(StatsD).to have_received(:increment)
          .with('api.claims_evidence.persist.failure', tags: base_tags + ['error_class:StandardError'])
      end

      it 'logs the failure with a scrubbed message and error_class' do
        allow(Logging::Helper::DataScrubber).to receive(:scrub).and_return('[scrubbed]')
        allow(Rails.logger).to receive(:error)

        service.call

        expect(Logging::Helper::DataScrubber).to have_received(:scrub).with('boom')
        expect(Rails.logger).to have_received(:error).with(
          'ClaimsEvidenceController#persist_evidence_submission failed',
          hash_including(document_type_id: doc_type_id, supplemental_claim_id: sc_id,
                         error_class: 'StandardError', error: '[scrubbed]')
        )
      end

      it 'captures the data needed to recreate the EvidenceSubmission by hand' do
        expect { service.call }.to change(PersonalInformationLog, :count).by(1)

        pii_log = PersonalInformationLog.last
        expect(pii_log.error_class).to eq('ClaimsEvidenceController#persist_evidence_submission')
        expect(pii_log.data).to include(
          'caseflow_claim_id' => sc_id,
          'user_account_id' => current_user.user_account_uuid,
          'icn' => current_user.icn,
          'document_type_id' => doc_type_id,
          'document_type' => 'Correspondence',
          'file_name' => 'doctors-note.pdf',
          'upload_status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
          'claims_evidence_uuid' => ce_success.body['uuid'],
          'claims_evidence_current_version_uuid' => ce_success.body['currentVersionUuid']
        )
        expect(pii_log.data['file_size']).to be > 0
      end

      context 'and the backfill capture also fails' do
        before { allow(PersonalInformationLog).to receive(:create).and_raise(StandardError.new('db down')) }

        it 'still returns the result rather than failing a document that was filed successfully' do
          expect(service.call.status).to eq(200)
        end

        it 'increments the unrecoverable counter and logs the CE uuid so the document can still be traced' do
          allow(StatsD).to receive(:increment).and_call_original
          allow(Rails.logger).to receive(:error)

          service.call

          expect(StatsD).to have_received(:increment)
            .with('api.claims_evidence.persist.unrecoverable', tags: base_tags + ['error_class:StandardError'])
          expect(Rails.logger).to have_received(:error).with(
            'ClaimsEvidenceController#capture_submission_for_backfill failed',
            hash_including(supplemental_claim_id: sc_id, user_account_uuid: current_user.user_account_uuid,
                           document_type_id: doc_type_id, claims_evidence_uuid: ce_success.body['uuid'],
                           error_class: 'StandardError')
          )
        end
      end
    end

    context 'when the response body cannot be read but the row was written' do
      let(:malformed_response) { double(reason_phrase: 'OK', status: 200, body: 'not-a-hash') }

      before do
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload).and_return(malformed_response)
      end

      it 'counts the call once, as a failure, rather than as both a success and a failure' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(TypeError)

        expect(StatsD).not_to have_received(:increment).with('api.claims_evidence.upload.success', anything)
        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['error_class:TypeError', "document_type_id:#{doc_type_id}"]
        )
      end

      it 'still persists the EvidenceSubmission because the document is already in the eFolder' do
        expect { service.call }.to raise_error(TypeError).and(change(EvidenceSubmission, :count).by(1))
      end
    end

    # The file is in the eFolder but nothing recorded it, so the lock is the only thing
    # standing between the Veteran and a duplicate. It must survive the error.
    context 'when the response body cannot be read and the row was not written' do
      let(:malformed_response) { double(reason_phrase: 'OK', status: 200, body: 'not-a-hash') }

      before do
        allow(EvidenceSubmission).to receive(:create!).and_raise(StandardError.new('boom'))
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload).and_return(malformed_response)
      end

      it 'raises, and keeps the lock so a retry is refused rather than uploaded twice' do
        expect { service.call }.to raise_error(TypeError)

        expect { described_class.new(current_user:, upload:, password:).call }
          .to raise_error(described_class::DuplicateUpload)
      end

      it 'counts the upload as a failure rather than a success' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(TypeError)

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['error_class:TypeError', "document_type_id:#{doc_type_id}"]
        )
        expect(StatsD).not_to have_received(:increment).with('api.claims_evidence.upload.success', anything)
      end

      it 'still captures the submission, with no uuid to record' do
        expect { service.call }.to raise_error(TypeError)
          .and(change(PersonalInformationLog, :count).by(1))

        pii_log = PersonalInformationLog.last
        expect(pii_log.data).to include(
          'caseflow_claim_id' => sc_id,
          'icn' => current_user.icn,
          'document_type_id' => doc_type_id,
          'file_name' => 'doctors-note.pdf',
          'claims_evidence_uuid' => nil,
          'claims_evidence_current_version_uuid' => nil
        )
      end

      it 'does not report the capture as unrecoverable' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(TypeError)

        expect(StatsD).not_to have_received(:increment).with(
          'api.claims_evidence.persist.unrecoverable', anything
        )
      end

      # Everything that can fail has: the row, the capture, and the body. The last-resort
      # handler has to report that rather than raise a second error on its way out.
      context 'and the backfill capture also fails' do
        before { allow(PersonalInformationLog).to receive(:create).and_raise(StandardError.new('db down')) }

        it 'reports it as unrecoverable and lets the original error surface' do
          allow(StatsD).to receive(:increment).and_call_original
          allow(Rails.logger).to receive(:error)

          expect { service.call }.to raise_error(TypeError)

          expect(StatsD).to have_received(:increment)
            .with('api.claims_evidence.persist.unrecoverable', tags: base_tags + ['error_class:StandardError'])
          expect(Rails.logger).to have_received(:error).with(
            'ClaimsEvidenceController#capture_submission_for_backfill failed',
            hash_including(supplemental_claim_id: sc_id, claims_evidence_uuid: nil,
                           error_class: 'StandardError')
          )
        end
      end
    end

    # The upload and the row both succeeded; only the lock cleanup broke. That must not
    # turn a request that did everything it was asked to into a failure.
    context 'when the cache raises while the lock is being released' do
      before { allow(cache).to receive(:delete).and_raise(ConnectionPool::TimeoutError.new('no slot')) }

      it 'persists the submission and does not count the upload as a failure' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to change(EvidenceSubmission, :count).by(1)

        expect(StatsD).not_to have_received(:increment).with('api.claims_evidence.upload.failure', anything)
      end
    end

    context 'when the cache is unavailable' do
      before { allow(cache).to receive(:write).and_return(nil) }

      it 'still allows the upload and records that the duplicate check was skipped' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to change(EvidenceSubmission, :count).by(1)

        expect(StatsD).to have_received(:increment)
          .with('api.claims_evidence.duplicate_check.skipped', tags: base_tags)
      end

      it 'still refuses a file that already landed on the claim' do
        service.call

        expect { described_class.new(current_user:, upload:, password:).call }
          .to raise_error(described_class::DuplicateUpload)
      end
    end
  end
end
