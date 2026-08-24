# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsEvidence::DuplicateCheck do
  subject(:duplicate_check) { build_check }

  let(:base_tags) { ClaimsEvidence::Metrics::TAGS }
  let(:user_account) { create(:user_account) }
  # A Struct, not a double — only these two readers are used.
  let(:user_struct) { Struct.new(:user_account, :user_account_uuid) }
  let(:current_user) { user_struct.new(user_account, user_account.id) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  # Match the factory defaults, so an unmodified factory row counts as a duplicate.
  # file is nil because DuplicateCheck never reads it.
  let(:upload_attrs) do
    { file: nil, doc_type_id: 34, sc_id: 'SC10879', document_type: 'Correspondence',
      file_name: 'doctors-note.pdf', file_size: 1234 }
  end

  def build_check(current_user: self.current_user, **overrides)
    described_class.new(
      current_user:,
      upload: ClaimsEvidence::UploadRequest.new(**upload_attrs.merge(overrides)),
      cache:
    )
  end

  describe '#presumed_duplicate?' do
    it 'does not flag an upload when the claim has no prior submissions' do
      expect(duplicate_check).not_to be_presumed_duplicate
    end

    context 'when a matching SUCCESS row exists' do
      before { create(:cst_sc_evidence_submission, user_account:) }

      it 'flags the upload as a duplicate' do
        expect(duplicate_check).to be_presumed_duplicate
      end

      it 'does not flag an upload with a different document type id' do
        expect(build_check(doc_type_id: 80, document_type: 'Photographs')).not_to be_presumed_duplicate
      end

      it 'does not flag an upload with a different file name' do
        expect(build_check(file_name: 'other-note.pdf')).not_to be_presumed_duplicate
      end

      it 'does not flag an upload with a different file size' do
        expect(build_check(file_size: 4321)).not_to be_presumed_duplicate
      end

      it 'does not flag an upload for a different supplemental claim' do
        expect(build_check(sc_id: 'SC99999')).not_to be_presumed_duplicate
      end
    end

    it 'ignores a matching row that belongs to another user' do
      create(:cst_sc_evidence_submission, user_account: create(:user_account))
      expect(duplicate_check).not_to be_presumed_duplicate
    end

    it 'ignores a row whose template_metadata is not valid JSON' do
      create(:cst_sc_evidence_submission, user_account:).update!(template_metadata: 'not json')
      expect(duplicate_check).not_to be_presumed_duplicate
    end

    it 'ignores a row whose template_metadata is not a JSON object' do
      create(:cst_sc_evidence_submission, user_account:).update!(template_metadata: '42')
      expect(duplicate_check).not_to be_presumed_duplicate
    end

    it 'ignores a row with no personalisation key' do
      create(:cst_sc_evidence_submission, user_account:).update!(template_metadata: '{"other":1}')
      expect(duplicate_check).not_to be_presumed_duplicate
    end
  end

  describe '#acquire_lock' do
    it 'claims the lease on the first call and refuses the second' do
      expect(duplicate_check.acquire_lock).to be(true)
      expect(build_check.acquire_lock).to be(false)
    end

    it 'does not block the same file when document type id differs' do
      duplicate_check.acquire_lock
      expect(build_check(doc_type_id: 80, document_type: 'Photographs').acquire_lock).to be(true)
    end

    it 'does not block a different file' do
      duplicate_check.acquire_lock
      expect(build_check(file_name: 'other-note.pdf').acquire_lock).to be(true)
    end

    it 'scopes the lease to the user' do
      duplicate_check.acquire_lock
      other_account = create(:user_account)
      other_user = user_struct.new(other_account, other_account.id)
      expect(build_check(current_user: other_user).acquire_lock).to be(true)
    end

    context 'when the cache returns nil' do
      before { allow(cache).to receive(:write).and_return(nil) }

      it 'allows the upload and records that the duplicate check was skipped' do
        allow(StatsD).to receive(:increment).and_call_original
        expect(duplicate_check.acquire_lock).to be(true)
        expect(StatsD).to have_received(:increment)
          .with('api.claims_evidence.duplicate_check.skipped', tags: base_tags)
      end
    end

    # RedisCacheStore swallows its own connection and pool errors, but the cache is
    # injectable and no other store promises that, so a raise has to be survivable.
    context 'when the cache raises' do
      before { allow(cache).to receive(:write).and_raise(ConnectionPool::TimeoutError.new('no slot')) }

      it 'allows the upload rather than failing the request' do
        expect(duplicate_check.acquire_lock).to be(true)
      end

      it 'records the check as skipped, tagged with the error class' do
        allow(StatsD).to receive(:increment).and_call_original
        duplicate_check.acquire_lock
        expect(StatsD).to have_received(:increment)
          .with('api.claims_evidence.duplicate_check.skipped',
                tags: base_tags + ['error_class:ConnectionPool::TimeoutError'])
      end
    end
  end

  describe '#release_lock' do
    it 'frees the lease so the same file can be retried' do
      duplicate_check.acquire_lock
      duplicate_check.release_lock
      expect(build_check.acquire_lock).to be(true)
    end

    # By now the file is in the eFolder, so this must never fail the request.
    context 'when the cache raises' do
      before { allow(cache).to receive(:delete).and_raise(ConnectionPool::TimeoutError.new('no slot')) }

      it 'swallows the error' do
        expect { duplicate_check.release_lock }.not_to raise_error
      end

      it 'records the release failure' do
        allow(StatsD).to receive(:increment).and_call_original
        duplicate_check.release_lock
        expect(StatsD).to have_received(:increment)
          .with('api.claims_evidence.duplicate_check.release_failure',
                tags: base_tags + ['error_class:ConnectionPool::TimeoutError'])
      end
    end
  end
end
