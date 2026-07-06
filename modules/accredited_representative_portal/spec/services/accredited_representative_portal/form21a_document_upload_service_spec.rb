# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::Form21aDocumentUploadService do
  let(:user) { create(:user) }
  let(:application_id) { '12345' }

  let(:in_progress_form) do
    create(:in_progress_form, form_id: '21a', user_uuid: user.uuid, form_data: form_data.to_json)
  end

  describe '.enqueue_uploads' do
    subject(:enqueue_uploads) do
      described_class.enqueue_uploads(in_progress_form:, application_id:)
    end

    context 'when form_data contains documents' do
      let(:form_data) do
        {
          'convictionDetailsDocuments' => [
            {
              'name' => 'conviction_doc.pdf',
              'confirmationCode' => 'guid-111',
              'size' => 12_345,
              'type' => 'application/pdf'
            }
          ],
          'courtMartialedDetailsDocuments' => [
            {
              'name' => 'court_martial.docx',
              'confirmationCode' => 'guid-222',
              'size' => 23_456,
              'type' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            },
            {
              'name' => 'court_martial_2.pdf',
              'confirmationCode' => 'guid-333',
              'size' => 34_567,
              'type' => 'application/pdf'
            }
          ]
        }
      end

      it 'enqueues a job for each document' do
        expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .to receive(:perform_async)
          .with('guid-111', application_id, 3, 'conviction_doc.pdf', 'application/pdf')

        expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .to receive(:perform_async)
          .with('guid-222', application_id, 4, 'court_martial.docx',
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document')

        expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .to receive(:perform_async)
          .with('guid-333', application_id, 4, 'court_martial_2.pdf', 'application/pdf')

        enqueue_uploads
      end

      it 'returns the count of enqueued jobs' do
        allow(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .to receive(:perform_async)

        expect(enqueue_uploads).to eq(3)
      end

      it 'logs the enqueuing activity' do
        allow(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .to receive(:perform_async)

        expect(Rails.logger).to receive(:info).with(/Enqueuing 3 document uploads/)
        expect(Rails.logger).to receive(:info).with(/Enqueued upload job.*guid-111/).once
        expect(Rails.logger).to receive(:info).with(/Enqueued upload job.*guid-222/).once
        expect(Rails.logger).to receive(:info).with(/Enqueued upload job.*guid-333/).once

        enqueue_uploads
      end

      it 'does not log original file names' do
        allow(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .to receive(:perform_async)
        allow(Rails.logger).to receive(:info)

        enqueue_uploads

        expect(Rails.logger).not_to have_received(:info).with(a_string_including('conviction_doc.pdf'))
        expect(Rails.logger).not_to have_received(:info).with(a_string_including('court_martial.docx'))
        expect(Rails.logger).not_to have_received(:info).with(a_string_including('court_martial_2.pdf'))
      end
    end

    context 'when form_data is empty' do
      let(:form_data) { {} }

      it 'returns 0 and does not enqueue any jobs' do
        expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .not_to receive(:perform_async)

        expect(enqueue_uploads).to eq(0)
      end
    end

    context 'when form_data is blank' do
      let(:in_progress_form) do
        form = create(:in_progress_form, form_id: '21a', user_uuid: user.uuid, form_data: '{}')
        # rubocop:disable Rails/SkipsModelValidations
        form.update_column(:form_data, '')
        # rubocop:enable Rails/SkipsModelValidations
        form.reload
      end

      let(:form_data) { nil }

      it 'returns 0 and does not enqueue any jobs' do
        expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .not_to receive(:perform_async)

        expect(enqueue_uploads).to eq(0)
      end
    end

    context 'when form_data contains no document arrays' do
      let(:form_data) do
        {
          'firstName' => 'John',
          'lastName' => 'Doe'
        }
      end

      it 'returns 0 and does not enqueue any jobs' do
        expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .not_to receive(:perform_async)

        expect(enqueue_uploads).to eq(0)
      end
    end

    context 'when form_data contains empty document arrays' do
      let(:form_data) do
        {
          'convictionDetailsDocuments' => [],
          'courtMartialedDetailsDocuments' => []
        }
      end

      it 'returns 0 and does not enqueue any jobs' do
        expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .not_to receive(:perform_async)

        expect(enqueue_uploads).to eq(0)
      end
    end

    context 'when form_data is invalid JSON' do
      let(:in_progress_form) do
        form = create(:in_progress_form, form_id: '21a', user_uuid: user.uuid, form_data: '{}')
        # rubocop:disable Rails/SkipsModelValidations
        form.update_column(:form_data, 'invalid json')
        # rubocop:enable Rails/SkipsModelValidations
        form.reload
      end

      let(:form_data) { nil }

      it 'logs an error and returns 0' do
        expect(Rails.logger).to receive(:error).with(/Failed to parse form_data/)
        expect(enqueue_uploads).to eq(0)
      end
    end

    context 'with all uploadable document types' do
      let(:pdf_type) { 'application/pdf' }
      let(:document_types) { AccreditedRepresentativePortal::Form21aDocumentUploadConstants::DOCUMENT_TYPES }

      let(:form_data) do
        document_types.keys.each_with_index.to_h do |key, idx|
          [
            key,
            [
              {
                'name' => "#{idx + 1}.pdf",
                'confirmationCode' => "guid-#{idx + 1}",
                'type' => pdf_type
              }
            ]
          ]
        end
      end

      it 'has a document type mapping for every Form 21a upload concern document key' do
        expected_keys = AccreditedRepresentativePortal::V0::Form21aUploadConcern::DOCUMENT_KEYS.values

        expect(document_types.keys).to match_array(expected_keys)
      end

      it 'enqueues jobs for all uploadable document types with correct document type codes' do
        allow(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
          .to receive(:perform_async)

        expect(enqueue_uploads).to eq(document_types.size)
        expect(document_types.size).to eq(13)
      end

      it 'maps each document key to the correct GCLAWS document type code' do
        document_types.each_with_index do |(_documents_key, document_type), idx|
          expect(AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob)
            .to receive(:perform_async)
            .with("guid-#{idx + 1}", application_id, document_type, "#{idx + 1}.pdf", pdf_type)
        end

        enqueue_uploads
      end
    end
  end
end
