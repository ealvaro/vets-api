# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::ClaimsEvidenceController, type: :controller do
  let(:user) { create(:user, :loa3, :legacy_icn) }
  let(:file) { fixture_file_upload('doctors-note.pdf') }
  let(:doc_type_id) { 34 }
  let(:sc_id) { 'SC10879' }
  let(:ce_success) { build(:claims_evidence_service_files_response, :success) }

  before do
    sign_in_as(user)
    allow(Common::VirusScan).to receive(:scan).and_return(true)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?)
      .with(:cst_supplemental_claims_evidence_upload, instance_of(User))
      .and_return(true)
    allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
      .to receive(:upload)
      .and_return(ce_success)
  end

  describe 'POST #create' do
    it 'releases the duplicate lock after successful upload and persistence' do
      duplicate_check = instance_double(ClaimsEvidence::DuplicateCheck,
                                        presumed_duplicate?: false,
                                        acquire_lock: true,
                                        release_lock: true)
      allow(ClaimsEvidence::DuplicateCheck).to receive(:new).and_return(duplicate_check)

      post :create, params: { file:, documentTypeId: doc_type_id, supplementalClaimId: sc_id }

      expect(response).to have_http_status(:ok)
      # retry_blocked:false — the row exists, so the DB layer covers a stranded lock.
      expect(duplicate_check).to have_received(:release_lock).with(retry_blocked: false).once
    end
  end
end
