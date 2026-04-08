# frozen_string_literal: true

require 'rails_helper'
require 'claims_evidence_api/service/files'
require 'claims_evidence_api/folder_identifier'
require 'claims_evidence_api/configuration'

RSpec.describe Remediation::BatchUploadProcessor, type: :service do
  let(:manifest_path) { Rails.root.join('spec', 'fixtures', 'remediation', 'valid_manifest.csv').to_s }
  let(:invalid_manifest_path) { Rails.root.join('spec', 'fixtures', 'remediation', 'invalid_manifest.csv').to_s }
  let(:duplicate_manifest_path) { Rails.root.join('spec', 'fixtures', 'remediation', 'duplicate_manifest.csv').to_s }
  let(:processor) { described_class.new(manifest_path:) }
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:ce_service) { instance_double(ClaimsEvidenceApi::Service::Files) }
  let(:breakers_service) { instance_double(Breakers::Service) }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
    allow(ClaimsEvidenceApi::Service::Files).to receive(:new).and_return(ce_service)
    allow(ce_service).to receive(:folder_identifier=)
    allow(ce_service).to receive(:upload) { double('response', body: { 'uuid' => SecureRandom.uuid }) }
    allow(ClaimsEvidenceApi::FolderIdentifier).to receive(:generate).and_return('folder-id')
    allow(Flipper).to receive(:enabled?).with(:clamav_scan_file_from_other_location).and_return(true)

    config_instance = instance_double(ClaimsEvidenceApi::Configuration)
    allow(ClaimsEvidenceApi::Configuration).to receive(:instance).and_return(config_instance)
    allow(config_instance).to receive(:breakers_service).and_return(breakers_service)
    allow(breakers_service).to receive(:latest_outage).and_return(nil)

    allow(Settings.remediation_batch_upload).to receive(:allowed_s3_buckets)
      .and_return('dsva-vetsgov-remediation-prod')

    allow(s3_client).to receive(:head_object).and_return(double('head', content_length: 1.megabyte))

    allow(s3_client).to receive(:get_object) do |args|
      File.write(args[:response_target], 'fake pdf content')
    end

    allow(RemediationBatchUploadItem).to receive(:with_advisory_lock).and_yield
  end

  describe '#run!' do
    it 'ingests manifest and processes items to completion' do
      processor.run!

      items = RemediationBatchUploadItem.all
      expect(items.count).to eq(3)
      expect(items.all? { |i| i.status == 'completed' }).to be true
      expect(items.all? { |i| i.claims_evidence_file_uuid.present? }).to be true
    end

    it 'respects LIMIT parameter' do
      limited = described_class.new(manifest_path:, limit: 1)
      limited.run!

      completed_count = RemediationBatchUploadItem.where(status: 'completed').count
      expect(completed_count).to eq(1)
    end

    it 'skips already-ingested rows on re-run (idempotent)' do
      create(:remediation_batch_upload_item, submission_id: 'SUB-000001', status: 'completed',
                                             claims_evidence_file_uuid: SecureRandom.uuid)

      processor.run!

      expect(RemediationBatchUploadItem.count).to eq(3)
      # The pre-existing one should not be re-uploaded
      expect(s3_client).not_to have_received(:get_object).with(hash_including(key: 'documents/001/evidence.pdf'))
    end
  end

  describe 'CSV ingestion' do
    it 'rejects rows with invalid data in the manifest' do
      invalid_processor = described_class.new(manifest_path: invalid_manifest_path)
      invalid_processor.run!

      # Invalid manifest has 3 rows, all should be rejected
      expect(RemediationBatchUploadItem.count).to eq(0)
    end

    it 'handles duplicate submission_ids in manifest without error' do
      dup_processor = described_class.new(manifest_path: duplicate_manifest_path)
      dup_processor.run!

      # Duplicate manifest has the same submission_id twice — second should be skipped
      expect(RemediationBatchUploadItem.where(submission_id: 'SUB-DUP-001').count).to eq(1)
    end
  end

  describe 'security validations' do
    it 'rejects path traversal in s3_key' do
      invalid_processor = described_class.new(manifest_path: invalid_manifest_path)
      invalid_processor.run!

      # The invalid manifest includes a row with '../' in the s3_key
      traversal_item = RemediationBatchUploadItem.find_by(submission_id: 'BAD-TRAVERSAL')
      expect(traversal_item).to be_nil
    end

    it 'rejects s3_buckets not in the allowlist' do
      invalid_processor = described_class.new(manifest_path: invalid_manifest_path)
      invalid_processor.run!

      wrong_bucket_item = RemediationBatchUploadItem.find_by(submission_id: 'BAD-BUCKET')
      expect(wrong_bucket_item).to be_nil
    end
  end

  describe 'error handling' do
    it 'records error details on S3 download failure' do
      allow(s3_client).to receive(:get_object).and_raise(Aws::S3::Errors::NoSuchKey.new(nil, 'key not found'))

      processor.run!

      item = RemediationBatchUploadItem.first
      expect(item.status).to eq('failed')
      expect(item.error_class).to eq('Aws::S3::Errors::NoSuchKey')
      expect(item.retry_count).to eq(1)
    end

    it 'records error details on CE API upload failure' do
      allow(ce_service).to receive(:upload).and_raise(Faraday::ServerError.new(nil, { status: 500 }))

      processor.run!

      item = RemediationBatchUploadItem.first
      expect(item.status).to eq('failed')
      expect(item.error_class).to eq('Faraday::ServerError')
    end

    it 'does not retry items that have reached MAX_RETRIES' do
      create(:remediation_batch_upload_item, :exhausted, submission_id: 'SUB-000001',
                                                         s3_key: 'documents/001/evidence.pdf')

      processor.run!

      item = RemediationBatchUploadItem.find_by(submission_id: 'SUB-000001')
      expect(item.status).to eq('failed')
      expect(item.retry_count).to eq(3)
      # Should not have been picked up by actionable scope
      expect(s3_client).not_to have_received(:get_object).with(hash_including(key: 'documents/001/evidence.pdf'))
    end
  end

  describe 'temp file cleanup' do
    around do |example|
      FileUtils.rm_f(Dir.glob(File.join(described_class::TEMP_DIR, 'upload_*')))
      example.run
    end

    it 'cleans up temp files even on upload error' do
      allow(ce_service).to receive(:upload).and_raise(StandardError, 'boom')

      processor.run!

      remaining = Dir.glob(File.join(described_class::TEMP_DIR, 'upload_*'))
      expect(remaining).to be_empty
    end
  end

  describe 'stale row recovery' do
    it 'resets stale downloading rows to pending and re-processes them' do
      # Use a submission_id from the manifest so file_number lookup works
      create(:remediation_batch_upload_item, :stale_downloading, submission_id: 'SUB-000001',
                                                                 s3_key: 'documents/001/evidence.pdf')

      processor.run!

      item = RemediationBatchUploadItem.find_by(submission_id: 'SUB-000001')
      expect(item.status).to eq('completed')
    end

    it 'resets stale uploading rows to pending and re-processes them' do
      create(:remediation_batch_upload_item, :stale_uploading, submission_id: 'SUB-000002',
                                                               s3_key: 'documents/002/supporting.pdf')

      processor.run!

      item = RemediationBatchUploadItem.find_by(submission_id: 'SUB-000002')
      expect(item.status).to eq('completed')
    end
  end

  describe 'stale temp file sweeping' do
    it 'deletes temp files older than 1 hour' do
      FileUtils.mkdir_p(described_class::TEMP_DIR)
      stale_path = File.join(described_class::TEMP_DIR, 'upload_stale_test')
      File.write(stale_path, 'old data')
      FileUtils.touch(stale_path, mtime: 2.hours.ago.to_time)

      processor.run!

      expect(File.exist?(stale_path)).to be false
    end
  end

  describe 'advisory lock' do
    it 'aborts when lock is already held' do
      allow(RemediationBatchUploadItem).to receive(:with_advisory_lock).and_return(false)

      expect { processor.run! }.to raise_error(SystemExit)
    end
  end

  describe 'preflight checks' do
    it 'aborts when ClamAV Flipper flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(:clamav_scan_file_from_other_location).and_return(false)

      expect { processor.run! }.to raise_error(SystemExit)
    end

    it 'aborts when circuit breaker is open' do
      outage = double('outage', end_time: nil)
      allow(breakers_service).to receive(:latest_outage).and_return(outage)

      expect { processor.run! }.to raise_error(SystemExit)
    end
  end

  describe 'circuit breaker handling during processing' do
    it 'pauses and retries on Breakers::OutageException' do
      call_count = 0
      allow(ce_service).to receive(:upload) do
        call_count += 1
        raise Breakers::OutageException if call_count == 1

        double('response', body: { 'uuid' => SecureRandom.uuid })
      end
      allow_any_instance_of(described_class).to receive(:sleep)

      processor.run!

      completed = RemediationBatchUploadItem.where(status: 'completed').count
      expect(completed).to be >= 1
    end
  end

  describe 'large file observability' do
    it 'logs a warning and emits a gauge for files exceeding the threshold' do
      allow(s3_client).to receive(:head_object)
        .and_return(double('head', content_length: 600.megabytes))
      allow(StatsD).to receive(:gauge)

      processor.run!

      expect(StatsD).to have_received(:gauge)
        .with('remediation.batch_upload.file_size_bytes', 600.megabytes)
        .at_least(:once)
    end
  end

  describe 'PII safety' do
    it 'does not persist file_number to the database' do
      processor.run!

      items = RemediationBatchUploadItem.all
      expect(items.count).to eq(3)
      # file_number is never stored — ciphertext column should be nil for all items
      items.each do |item|
        expect(item[:file_number_ciphertext]).to be_nil if item.has_attribute?(:file_number_ciphertext)
      end
    end

    it 'still passes file_number to Claims Evidence API at upload time' do
      processor.run!

      expect(ClaimsEvidenceApi::FolderIdentifier).to have_received(:generate)
        .with('VETERAN', 'FILENUMBER', '123456789').at_least(:once)
    end

    it 'redacts file numbers from error messages' do
      error_with_pii = StandardError.new('Error for veteran 123456789 at /path')
      allow(s3_client).to receive(:get_object).and_raise(error_with_pii)

      processor.run!

      item = RemediationBatchUploadItem.first
      expect(item.error_message).not_to include('123456789')
      expect(item.error_message).to include('[REDACTED]')
    end
  end

  describe '.print_status' do
    it 'prints summary without errors' do
      create(:remediation_batch_upload_item, status: 'completed')
      create(:remediation_batch_upload_item, status: 'failed', retry_count: 1)
      create(:remediation_batch_upload_item, :exhausted)

      expect { described_class.print_status }.to output(/BATCH UPLOAD STATUS/).to_stdout
    end
  end

  describe 'dry run' do
    it 'validates manifest without creating records or uploading files' do
      dry_processor = described_class.new(manifest_path:, dry_run: true)
      allow(s3_client).to receive(:head_object)

      dry_processor.run!

      expect(RemediationBatchUploadItem.count).to eq(0)
      expect(ce_service).not_to have_received(:upload)
    end
  end
end
