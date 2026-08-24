# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EvidenceSubmission, type: :model do
  let(:user_account) { create(:user_account) }
  let(:success) { BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS] }

  describe 'scopes' do
    let!(:lighthouse_row) { create(:bd_evidence_submission, upload_status: success) }
    let!(:caseflow_row) { create(:cst_sc_evidence_submission, user_account:) }

    describe '.without_caseflow_claim' do
      it 'returns only rows without a caseflow_claim_id' do
        expect(described_class.without_caseflow_claim).to contain_exactly(lighthouse_row)
      end
    end

    describe '.completed' do
      # SUCCESS is the one lifecycle status Caseflow SC rows share with Lighthouse rows,
      # so this scope is chained through without_caseflow_claim to keep them separate.
      it 'excludes caseflow-scoped rows' do
        expect(described_class.completed).not_to include(caseflow_row)
      end
    end
  end

  describe 'template_metadata round-trip' do
    it 'stores a JSON string on write and returns a JSON string on read (Lockbox does not auto-decode)' do
      row = create(:cst_sc_evidence_submission, user_account:, file_name: 'note.pdf')
      row.reload
      expect(row.template_metadata).to be_a(String)
      expect(JSON.parse(row.template_metadata))
        .to eq('personalisation' => { 'file_name' => 'note.pdf',
                                      'document_type_id' => 34,
                                      'document_type' => 'Correspondence' })
    end
  end
end
