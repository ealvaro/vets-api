# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitsDocuments::Providers::IvcChampva::IvcChampvaBenefitsDocumentsProvider do
  subject(:provider) { described_class.new(user) }

  let(:user_icn) { '1012667145V762142' }
  let(:user_account) { create(:user_account) }
  let(:user) { create(:user, :loa3, :accountable, user_account:, icn: user_icn) }
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
    allow(EvidenceSubmission).to receive(:create)
    allow(Rails.application).to receive(:call).and_return([200, {}, []])
    allow(Flipper).to receive(:enabled?)
      .with(:benefits_documents_ivc_champva_docs_only_resubmission, user)
      .and_return(true)
  end

  describe '#queue_document_upload' do
    it 'routes UUID claim IDs to CHAMPVA form records and uploads as military records attachment' do
      form_record = instance_double(
        IvcChampvaForm,
        id: 42,
        form_number: '10-10D-EXTENDED-EXISTING',
        form_uuid: 'uuid-claim',
        submitted_by_icn: user_icn
      )
      where_scope = instance_double(ActiveRecord::Relation)
      ordered_scope = instance_double(ActiveRecord::Relation)
      allow(IvcChampvaForm).to receive(:where).with(form_uuid: 'uuid-claim').and_return(where_scope)
      allow(where_scope).to receive(:order).with(updated_at: :desc).and_return(ordered_scope)
      allow(ordered_scope).to receive(:first).and_return(form_record)

      result = provider.queue_document_upload(
        claim_id: 'uuid-claim',
        file: uploaded_file,
        document_type: 'Supporting document'
      )

      expect(result).to eq({ jid: 'guid-123' })
      expect(PersistentAttachments::MilitaryRecords).to have_received(:new).with(form_id: '10-10D-EXTENDED')
      expect(attachment).to have_received(:file=).with(uploaded_file)
      expect(Rails.application).to have_received(:call)
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
      form_record = instance_double(
        IvcChampvaForm,
        id: 99,
        form_number: 'NOT-SUPPORTED',
        form_uuid: 'uuid-claim',
        submitted_by_icn: user_icn
      )
      where_scope = instance_double(ActiveRecord::Relation)
      ordered_scope = instance_double(ActiveRecord::Relation)
      allow(IvcChampvaForm).to receive(:where).with(form_uuid: 'uuid-claim').and_return(where_scope)
      allow(where_scope).to receive(:order).with(updated_at: :desc).and_return(ordered_scope)
      allow(ordered_scope).to receive(:first).and_return(form_record)

      expect do
        provider.queue_document_upload(claim_id: 'uuid-claim', file: uploaded_file)
      end.to raise_error(Common::Exceptions::UnprocessableEntity)
    end

    it 'raises unprocessable entity when docs-only resubmission endpoint fails' do
      form_record = instance_double(
        IvcChampvaForm,
        id: 42,
        form_number: '10-10D-EXTENDED-EXISTING',
        form_uuid: 'uuid-claim',
        submitted_by_icn: user_icn
      )
      where_scope = instance_double(ActiveRecord::Relation)
      ordered_scope = instance_double(ActiveRecord::Relation)
      allow(IvcChampvaForm).to receive(:where).with(form_uuid: 'uuid-claim').and_return(where_scope)
      allow(where_scope).to receive(:order).with(updated_at: :desc).and_return(ordered_scope)
      allow(ordered_scope).to receive(:first).and_return(form_record)
      allow(Rails.application).to receive(:call).and_return([422, {}, ['bad']])

      expect do
        provider.queue_document_upload(claim_id: 'uuid-claim', file: uploaded_file)
      end.to raise_error(Common::Exceptions::UnprocessableEntity)
    end

    it 'does not call docs-only resubmission endpoint when the flag is disabled' do
      form_record = instance_double(
        IvcChampvaForm,
        id: 42,
        form_number: '10-10D-EXTENDED-EXISTING',
        form_uuid: 'uuid-claim',
        submitted_by_icn: user_icn
      )
      where_scope = instance_double(ActiveRecord::Relation)
      ordered_scope = instance_double(ActiveRecord::Relation)
      allow(IvcChampvaForm).to receive(:where).with(form_uuid: 'uuid-claim').and_return(where_scope)
      allow(where_scope).to receive(:order).with(updated_at: :desc).and_return(ordered_scope)
      allow(ordered_scope).to receive(:first).and_return(form_record)
      allow(Flipper).to receive(:enabled?)
        .with(:benefits_documents_ivc_champva_docs_only_resubmission, user)
        .and_return(false)

      result = provider.queue_document_upload(claim_id: 'uuid-claim', file: uploaded_file)

      expect(result).to eq({ jid: 'guid-123' })
      expect(Rails.application).not_to have_received(:call)
    end
  end
end
