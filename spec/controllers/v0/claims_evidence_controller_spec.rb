# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::ClaimsEvidenceController, type: :controller do
  let(:user) { create(:user, :loa3, :legacy_icn) }
  let(:file) { fixture_file_upload('doctors-note.pdf') }
  let(:doc_type_id) { 34 }
  let(:sc_id) { 'SC10879' }
  let(:base_tags) { ClaimsEvidence::Metrics::TAGS }

  before do
    sign_in_as(user)
    allow(Common::VirusScan).to receive(:scan).and_return(true)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?)
      .with(:cst_supplemental_claims_evidence_upload, instance_of(User))
      .and_return(true)
    # No Claims Evidence stub: every example here is rejected before the upload service runs.
    expect_any_instance_of(ClaimsEvidenceApi::Service::Files).not_to receive(:upload)
  end

  def post_create(**overrides)
    params = { file:, documentTypeId: doc_type_id, supplementalClaimId: sc_id }.merge(overrides).compact
    post :create, params:
  end

  describe 'POST #create' do
    describe 'the validation failure counter' do
      before { allow(StatsD).to receive(:increment).and_call_original }

      def expect_validation_failure(reason)
        expect(StatsD).to have_received(:increment).with(
          'api.claims_evidence.validation.failure', tags: base_tags + ["reason:#{reason}"]
        )
      end

      it 'counts a missing file' do
        post_create(file: nil)
        expect_validation_failure('missing_file')
      end

      it 'counts a file param that is not an upload' do
        post_create(file: 'not-a-file')
        expect_validation_failure('invalid_file')
      end

      it 'counts an empty file' do
        post_create(file: fixture_file_upload('empty-file.jpg', 'image/jpeg'))
        expect_validation_failure('empty_file')
      end

      it 'counts a file over the size limit' do
        stub_const('V0::ClaimsEvidenceController::MAX_FILE_SIZE', 10)
        post_create
        expect_validation_failure('file_too_large')
      end

      it 'counts an unsupported file type' do
        post_create(file: fixture_file_upload('va.gif', 'image/gif'))
        expect_validation_failure('unsupported_file_type')
      end

      it 'counts a missing documentTypeId' do
        post_create(documentTypeId: nil)
        expect_validation_failure('missing_document_type_id')
      end

      it 'counts a malformed documentTypeId' do
        post_create(documentTypeId: '34abc')
        expect_validation_failure('malformed_document_type_id')
      end

      it 'counts an unsupported documentTypeId' do
        post_create(documentTypeId: 9999)
        expect_validation_failure('unsupported_document_type_id')
      end

      it 'counts a missing supplementalClaimId' do
        post_create(supplementalClaimId: nil)
        expect_validation_failure('missing_supplemental_claim_id')
      end

      it 'counts a malformed supplementalClaimId' do
        post_create(supplementalClaimId: 'foo')
        expect_validation_failure('malformed_supplemental_claim_id')
      end

      it 'counts a PDF rejection under the reason the unlocker gives' do
        allow_any_instance_of(ClaimsEvidence::PdfUnlocker).to receive(:unlock!).and_raise(
          ClaimsEvidence::PdfUnlocker::Rejected.new(reason: 'incorrect_password',
                                                    code: 'DOC_UPLOAD_INCORRECT_PASSWORD')
        )

        post_create(password: 'wrong')

        expect_validation_failure('incorrect_password')
        expect(StatsD).not_to have_received(:increment).with(
          'api.claims_evidence.upload.failure', anything
        )
      end
    end
  end
end
