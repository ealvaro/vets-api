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
        ), content_name: anything)
        .and_return(ce_success)
      service.call
    end

    it 'dates the document in the Claims Evidence timezone rather than UTC' do
      Timecop.freeze(Time.utc(2026, 3, 15, 2, 0, 0)) do
        expect_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload)
          .with(anything, provider_data: hash_including(dateVaReceivedDocument: '2026-03-14'),
                          content_name: anything)
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

      it 'releases with retry_blocked true when the outcome is unknown' do
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
          .to receive(:upload).and_raise(Faraday::TimeoutError)

        expect { service.call }.to raise_error(Faraday::TimeoutError)

        expect(duplicate_check).to have_received(:release_lock).with(retry_blocked: true).once
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

    describe 'the record lifecycle' do
      def last_status = EvidenceSubmission.last&.upload_status

      # Retention runs from successful submission, not creation, so a document filed later than
      # the row was written keeps a full 60 days from the moment it landed.
      it 'anchors the delete date to the successful submission', run_at: '2026-01-01T12:00:00Z' do
        filed_at = Time.zone.parse('2026-01-01T15:00:00Z')

        allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload) do
          Timecop.freeze(filed_at)
          ce_success
        end

        service.call

        expect(EvidenceSubmission.last.delete_date).to be_within(1.minute).of(filed_at + 60.days)
      end

      it 'writes the record as CREATED before the upload and SUCCESS after it' do
        seen = nil
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload) do
          seen = last_status
          ce_success
        end

        service.call

        expect(seen).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED])
        expect(last_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS])
      end

      it 'records the sanitized contentName so the document can be found again' do
        service.call

        metadata = JSON.parse(EvidenceSubmission.last.template_metadata)
        expect(metadata.dig('personalisation', 'content_name')).to eq('doctors-note.pdf')
        expect(metadata.dig('personalisation', 'file_name')).to eq('doctors-note.pdf')
      end

      it 'does not send anything to Claims Evidence if the record cannot be written' do
        allow(EvidenceSubmission).to receive(:create!).and_raise(ActiveRecord::RecordNotSaved)
        expect_any_instance_of(ClaimsEvidenceApi::Service::Files).not_to receive(:upload)

        expect { service.call }.to raise_error(ActiveRecord::RecordNotSaved)
      end

      # A 4xx is Claims Evidence telling us the document was not filed.
      it 'deletes the record when Claims Evidence rejects the upload' do
        rejection = Common::Client::Errors::ClientError.new('VEFSERR40012', 400, { 'code' => 'VEFSERR40012' })
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload).and_raise(rejection)

        expect { service.call }.to raise_error(Common::Client::Errors::ClientError)
          .and(not_change(EvidenceSubmission, :count))
      end

      # All reach the service as a ClientError alongside the 4xx above; the status separates them.
      describe 'when the outcome of the upload is unknown' do
        def expect_record_left_created(error)
          allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload).and_raise(error)

          expect { service.call }.to raise_error(error.class)
            .and(change(EvidenceSubmission, :count).by(1))

          expect(last_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED])
        end

        it 'leaves the record CREATED when Claims Evidence fails' do
          expect_record_left_created(build(:claims_evidence_service_files_error, :error)) # 503
        end

        it 'leaves the record CREATED when the connection drops without a status' do
          expect_record_left_created(Common::Client::Errors::ClientError.new('Connection failed'))
        end

        # The document is filed; only the answer describing it was unreadable.
        it 'leaves the record CREATED when the response cannot be parsed' do
          expect_record_left_created(Common::Client::Errors::ParsingError.new('unparseable', 200))
        end

        # Common::Client::Base raises this rather than letting Faraday::TimeoutError escape.
        it 'leaves the record CREATED when the request times out' do
          expect_record_left_created(Common::Exceptions::GatewayTimeout.new)
        end
      end

      it 'still returns the result when only the status update fails' do
        allow(StatsD).to receive(:increment).and_call_original
        allow_any_instance_of(EvidenceSubmission).to receive(:update!).and_raise(StandardError.new('boom'))

        expect(service.call.status).to eq(200)

        expect(StatsD).to have_received(:increment)
          .with('api.claims_evidence.persist.failure', tags: base_tags + ['error_class:StandardError'])
      end
    end

    describe 'when Claims Evidence says the name is taken' do
      let(:collision) do
        Common::Client::Errors::ClientError.new(
          'VEFSERR40018', 400,
          { 'code' => 'VEFSERR40018', 'message' => 'Document already exists by ownerId and contentName' }
        )
      end

      before do
        allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload).and_raise(collision)
      end

      it 'raises ContentNameTaken and leaves no record behind' do
        expect { service.call }.to raise_error(described_class::ContentNameTaken)
          .and(not_change(EvidenceSubmission, :count))
      end

      it 'counts the failure' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(described_class::ContentNameTaken)

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['reason:content_name_taken', "document_type_id:#{doc_type_id}"]
        )
      end
    end

    context 'when the filename has no usable ASCII equivalent' do
      let(:upload) do
        ClaimsEvidence::UploadRequest.new(
          file:, doc_type_id:, sc_id:, file_name: '日本語.pdf', file_size: file.size
        )
      end

      it 'counts the failure and writes no record' do
        allow(StatsD).to receive(:increment).and_call_original

        expect { service.call }.to raise_error(ClaimsEvidence::ContentName::Unsupported)
          .and(not_change(EvidenceSubmission, :count))

        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.upload.failure',
          tags: base_tags + ['reason:unsupported_name', "document_type_id:#{doc_type_id}"]
        )
      end
    end

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
    context 'when a parallel request holds the lock' do
      before do
        allow_any_instance_of(ClaimsEvidence::DuplicateCheck).to receive(:acquire_lock).and_return(false)
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
