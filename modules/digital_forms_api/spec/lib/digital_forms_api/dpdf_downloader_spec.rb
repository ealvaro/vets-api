# frozen_string_literal: true

require 'rails_helper'
require 'digital_forms_api/dpdf_downloader'

RSpec.describe DigitalFormsApi::DpdfDownloader do
  subject(:downloader) { described_class.new(claim) }

  let(:claim) { create(:add_remove_dependents_claim) }
  let(:file_uuid) { 'form-dpdf-uuid' }
  let(:version) { 'version-uuid-456' }
  let(:pdf_bytes) { '%PDF-1.4 fake-bytes' }
  let(:files) { instance_double(ClaimsEvidenceApi::Service::Files) }
  let(:response_struct) { Struct.new(:body) }

  before { allow(ClaimsEvidenceApi::Service::Files).to receive(:new).and_return(files) }

  # Helper: a claims_evidence_api_submissions row for this claim.
  def ce_submission(persistent_attachment_id:, va_claim_id:)
    create(:claims_evidence_submission, saved_claim_id: claim.id, form_id: claim.form_id,
                                        persistent_attachment_id:, va_claim_id:)
  end

  describe '#fetch' do
    context 'when the claim also has supporting-evidence and pending rows on the same saved_claim_id' do
      before do
        ce_submission(persistent_attachment_id: 99, va_claim_id: 'attachment-uuid') # supporting doc — ignore
        ce_submission(persistent_attachment_id: nil, va_claim_id: nil)              # pending form row — ignore
        ce_submission(persistent_attachment_id: nil, va_claim_id: file_uuid)        # the filed form dPDF — want

        allow(files).to receive(:retrieve).with(file_uuid)
                                          .and_return(response_struct.new({ 'currentVersionUuid' => version }))
        allow(files).to receive(:download).with(file_uuid, version).and_return(response_struct.new(pdf_bytes))
      end

      it 'downloads the filed form-level dPDF, not a supporting attachment' do
        expect(downloader.fetch).to eq(pdf_bytes)
      end
    end

    context 'when the claim only has supporting-evidence rows filed' do
      before { ce_submission(persistent_attachment_id: 1, va_claim_id: 'attachment-uuid') }

      it 'raises NotFiled without calling Claims Evidence' do
        expect(files).not_to receive(:retrieve)
        expect { downloader.fetch }.to raise_error(described_class::NotFiled)
      end
    end

    context 'when the form-level dPDF is filed but has no current version' do
      before do
        ce_submission(persistent_attachment_id: nil, va_claim_id: file_uuid)
        allow(files).to receive(:retrieve).with(file_uuid).and_return(response_struct.new({}))
      end

      it 'raises NotFiled without attempting the download' do
        expect(files).not_to receive(:download)
        expect { downloader.fetch }.to raise_error(described_class::NotFiled)
      end
    end
  end
end
