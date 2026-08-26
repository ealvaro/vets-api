# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitsDocuments::Providers::IvcChampva::IvcChampvaBenefitsDocumentsProvider do
  subject(:provider) { described_class.new(user) }

  let(:user_icn) { '1012667145V762142' }
  let(:user_account) { create(:user_account) }
  let(:user) { create(:user, :loa3, :accountable, user_account:, icn: user_icn) }
  let(:docs_only_resubmission_service) { instance_double(IvcChampva::DocsOnlyResubmissionService) }
  let(:uploaded_file) { instance_double(ActionDispatch::Http::UploadedFile, original_filename: 'note.pdf') }
  let(:attachment) do
    instance_double(
      PersistentAttachments::MilitaryRecords,
      valid?: true,
      save: true,
      guid: 'guid-123',
      file: uploaded_file
    )
  end

  before do
    allow(user).to receive(:user_account_uuid).and_return(user_account.id)
    allow(UserAccount).to receive(:find_by).with(id: user_account.id).and_return(user_account)
    allow(PersistentAttachments::MilitaryRecords).to receive(:new).and_return(attachment)
    allow(attachment).to receive(:file=)
    allow(BenefitsDocuments::Utilities::Helpers).to receive_messages(
      generate_obscured_file_name: 'obf.pdf',
      format_date_for_mailers: 'May 1, 2026'
    )
    allow(EvidenceSubmission).to receive(:create!)
    allow(IvcChampva::DocsOnlyResubmissionService).to receive(:new)
      .with(current_user: user)
      .and_return(docs_only_resubmission_service)
    allow(docs_only_resubmission_service).to receive(:call).and_return({ json: {}, status: 200 })
    allow(Flipper).to receive(:enabled?)
      .with(:benefits_documents_ivc_champva_docs_only_resubmission, user)
      .and_return(true)
  end

  describe '#queue_document_upload' do
    def stub_champva_form_record(form_number:, form_uuid: 'uuid-claim', id: 42)
      form_record = instance_double(
        IvcChampvaForm,
        id:,
        form_number:,
        form_uuid:,
        submitted_by_icn: user_icn
      )
      where_scope = instance_double(ActiveRecord::Relation)
      ordered_scope = instance_double(ActiveRecord::Relation)
      allow(IvcChampvaForm).to receive(:where).with(form_uuid:).and_return(where_scope)
      allow(where_scope).to receive(:order).with(updated_at: :desc).and_return(ordered_scope)
      allow(ordered_scope).to receive(:first).and_return(form_record)
      form_record
    end

    it 'routes UUID claim IDs to CHAMPVA form records and uploads as military records attachment' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')

      result = provider.queue_document_upload(
        claim_id: 'uuid-claim',
        file: uploaded_file,
        document_type: 'Supporting document',
        applicants: '["Michael Myers"]'
      )

      expect(result).to eq({ jid: 'guid-123' })
      expect(PersistentAttachments::MilitaryRecords).to have_received(:new).with(form_id: '10-10D-EXTENDED')
      expect(attachment).to have_received(:file=).with(uploaded_file)
      expect(docs_only_resubmission_service).to have_received(:call).with(
        hash_including(
          'supporting_docs' => [
            hash_including('applicants' => ['Michael Myers'])
          ]
        )
      )
    end

    it 'supports supplemental CHAMPVA form numbers' do
      stub_champva_form_record(form_number: '10-10D-SUPPLEMENTAL-EXISTING')

      result = provider.queue_document_upload(
        claim_id: 'uuid-claim',
        file: uploaded_file
      )

      expect(result).to eq({ jid: 'guid-123' })
      expect(PersistentAttachments::MilitaryRecords).to have_received(:new)
        .with(form_id: '10-10D-SUPPLEMENTAL-EXISTING')
    end

    [nil, [], ['one.pdf', 'two.pdf'], '/tmp/request-controlled.pdf', { path: '/tmp/document.pdf' }].each do |file|
      it "rejects invalid single-file input #{file.inspect} before creating upload records" do
        expect do
          provider.queue_document_upload(claim_id: 'uuid-claim', file:)
        end.to raise_error(Common::Exceptions::UnprocessableEntity) { |error|
          expect(error.errors.first[:detail]).to eq('file must contain exactly one uploaded document')
        }

        expect(PersistentAttachments::MilitaryRecords).not_to have_received(:new)
        expect(EvidenceSubmission).not_to have_received(:create!)
        expect(docs_only_resubmission_service).not_to have_received(:call)
      end
    end

    [
      ['malformed JSON', '["Michael Myers"'],
      ['non-array JSON', '{"name":"Michael Myers"}'],
      ['multiple applicants', '["Michael Myers","Freddy Krueger"]'],
      ['a blank applicant', '[""]']
    ].each do |description, applicants|
      it "rejects #{description} before creating upload records" do
        stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')

        expect do
          provider.queue_document_upload(
            claim_id: 'uuid-claim',
            file: uploaded_file,
            applicants:
          )
        end.to raise_error(Common::Exceptions::UnprocessableEntity) { |error|
          expect(error.errors.first[:detail])
            .to eq('applicants must be a JSON array containing at most one non-blank string')
        }

        expect(attachment).not_to have_received(:save)
        expect(EvidenceSubmission).not_to have_received(:create!)
        expect(docs_only_resubmission_service).not_to have_received(:call)
      end
    end

    it 'allows a docs-only upload without an applicant when applicant metadata is unavailable' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')

      result = provider.queue_document_upload(
        claim_id: 'uuid-claim',
        file: uploaded_file,
        applicants: []
      )

      expect(result).to eq({ jid: 'guid-123' })
      expect(docs_only_resubmission_service).to have_received(:call).with(
        hash_including(
          'supporting_docs' => [hash_including('applicants' => [])]
        )
      )
    end

    it 'persists evidence submission bookkeeping after PEGA is triggered' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')
      expect(docs_only_resubmission_service).to receive(:call).ordered.and_return({ json: {}, status: 200 })
      expect(EvidenceSubmission).to receive(:create!).ordered.with(
        hash_including(
          upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
          delete_date: instance_of(ActiveSupport::TimeWithZone)
        )
      )

      provider.queue_document_upload(
        claim_id: 'uuid-claim',
        file: uploaded_file,
        applicants: ['Michael Myers']
      )
    end

    it 'logs and meters bookkeeping failures without changing a successful response' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')
      allow(EvidenceSubmission).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(EvidenceSubmission.new))
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)

      result = provider.queue_document_upload(
        claim_id: 'uuid-claim',
        file: uploaded_file,
        applicants: ['Michael Myers']
      )

      expect(result).to eq({ jid: 'guid-123' })
      expect(docs_only_resubmission_service).to have_received(:call)
      expect(Rails.logger).to have_received(:error).with(
        'Failed to persist CHAMPVA evidence submission',
        error_class: 'ActiveRecord::RecordInvalid',
        error: instance_of(String)
      )
      expect(StatsD).to have_received(:increment).with(
        described_class::EVIDENCE_SUBMISSION_FAILURE_METRIC,
        tags: ['error_class:ActiveRecord::RecordInvalid']
      )
      expect(StatsD).to have_received(:increment).with(
        'silent_failure',
        tags: ['service:claim-status', 'function: Failed to persist CHAMPVA evidence submission']
      )
    end

    it 'supports numeric claim IDs that map directly to ivc_champva_form ids' do
      form_record = instance_double(
        IvcChampvaForm,
        id: 123,
        form_number: '10-7959A',
        form_uuid: 'uuid-claim',
        submitted_by_icn: user_icn
      )
      allow(IvcChampvaForm).to receive(:find_by).with(id: form_record.id).and_return(form_record)

      result = provider.queue_document_upload(
        claim_id: form_record.id.to_s,
        file: uploaded_file
      )

      expect(result).to eq({ jid: 'guid-123' })
      expect(PersistentAttachments::MilitaryRecords).to have_received(:new).with(form_id: '10-7959A')
    end

    it 'raises resource not found when a numeric claim ID belongs to another user' do
      form_record = instance_double(
        IvcChampvaForm,
        id: 123,
        submitted_by_icn: '1012667145V762143'
      )
      allow(IvcChampvaForm).to receive(:find_by).with(id: form_record.id).and_return(form_record)

      expect do
        provider.queue_document_upload(claim_id: form_record.id.to_s, file: uploaded_file)
      end.to raise_error(Common::Exceptions::ResourceNotFound)
    end

    it 'supports legacy claim records without a submitted ICN' do
      form_record = instance_double(
        IvcChampvaForm,
        id: 123,
        form_number: '10-7959A',
        form_uuid: 'uuid-claim',
        submitted_by_icn: nil
      )
      allow(IvcChampvaForm).to receive(:find_by).with(id: form_record.id).and_return(form_record)

      result = provider.queue_document_upload(claim_id: form_record.id.to_s, file: uploaded_file)

      expect(result).to eq({ jid: 'guid-123' })
    end

    it 'raises unprocessable entity for unsupported CHAMPVA form numbers' do
      stub_champva_form_record(form_number: 'NOT-SUPPORTED', id: 99)

      expect do
        provider.queue_document_upload(claim_id: 'uuid-claim', file: uploaded_file)
      end.to raise_error(Common::Exceptions::UnprocessableEntity)
    end

    it 'raises unprocessable entity when docs-only resubmission fails' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')
      pega_failure = { json: { error_message: 'bad' }, status: 422 }
      expect(docs_only_resubmission_service).to receive(:call).ordered.and_return(pega_failure)

      expect do
        provider.queue_document_upload(
          claim_id: 'uuid-claim',
          file: uploaded_file,
          applicants: ['Michael Myers']
        )
      end.to raise_error(Common::Exceptions::UnprocessableEntity) { |error|
        expect(error.errors.first[:detail]).to eq('CHAMPVA docs-only resubmission failed: bad')
      }
      expect(EvidenceSubmission).not_to have_received(:create!)
    end

    it 'uses a generic error detail when docs-only resubmission returns no error message' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')
      allow(docs_only_resubmission_service).to receive(:call)
        .and_return({ json: {}, status: 500 })

      expect do
        provider.queue_document_upload(
          claim_id: 'uuid-claim',
          file: uploaded_file,
          applicants: ['Michael Myers']
        )
      end.to raise_error(Common::Exceptions::UnprocessableEntity) { |error|
        expect(error.errors.first[:detail]).to eq('CHAMPVA docs-only resubmission failed')
      }
    end

    it 'does not call docs-only resubmission service when the flag is disabled' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')
      allow(Flipper).to receive(:enabled?)
        .with(:benefits_documents_ivc_champva_docs_only_resubmission, user)
        .and_return(false)

      result = provider.queue_document_upload(claim_id: 'uuid-claim', file: uploaded_file)

      expect(result).to eq({ jid: 'guid-123' })
      expect(docs_only_resubmission_service).not_to have_received(:call)
      expect(EvidenceSubmission).to have_received(:create!).with(
        hash_including(upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED])
      )
    end

    it 'unlocks password-protected PDF uploads before attachment validation' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')
      tempfile = instance_double(Tempfile, path: '/tmp/source.pdf', unlink: true)
      unlocked_tempfile = instance_double(Tempfile, path: '/tmp/unlocked.pdf')
      pdf_file = instance_double(
        ActionDispatch::Http::UploadedFile,
        original_filename: 'locked.pdf',
        tempfile:
      )
      pdftk = double('PdfForms')

      allow(pdf_file).to receive(:tempfile=)
      allow(Tempfile).to receive(:new).and_return(unlocked_tempfile)
      allow(PdfForms).to receive(:new).and_return(pdftk)
      allow(pdftk).to receive(:call_pdftk)

      result = provider.queue_document_upload(
        claim_id: 'uuid-claim',
        file: pdf_file,
        password: 'secret',
        applicants: ['Michael Myers']
      )

      expect(result).to eq({ jid: 'guid-123' })
      expect(pdftk).to have_received(:call_pdftk)
        .with('/tmp/source.pdf', 'input_pw', 'secret', 'output', '/tmp/unlocked.pdf')
      expect(tempfile).to have_received(:unlink)
      expect(pdf_file).to have_received(:tempfile=).with(unlocked_tempfile)
      expect(attachment).to have_received(:file=).with(pdf_file)
    end

    it 'raises unprocessable entity when a PDF password is incorrect' do
      stub_champva_form_record(form_number: '10-10D-EXTENDED-EXISTING')
      tempfile = instance_double(Tempfile, path: '/tmp/source.pdf')
      unlocked_tempfile = instance_double(Tempfile, path: '/tmp/unlocked.pdf')
      pdf_file = instance_double(
        ActionDispatch::Http::UploadedFile,
        original_filename: 'locked.pdf',
        tempfile:
      )
      pdftk = double('PdfForms')

      allow(Tempfile).to receive(:new).and_return(unlocked_tempfile)
      allow(PdfForms).to receive(:new).and_return(pdftk)
      allow(pdftk).to receive(:call_pdftk).and_raise(PdfForms::PdftkError)

      expect do
        provider.queue_document_upload(
          claim_id: 'uuid-claim',
          file: pdf_file,
          password: 'wrong',
          applicants: ['Michael Myers']
        )
      end.to raise_error(Common::Exceptions::UnprocessableEntity)
    end
  end
end
