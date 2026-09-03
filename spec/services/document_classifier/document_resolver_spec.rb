# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentClassifier::DocumentResolver do
  subject(:resolver) { described_class.new(upload:, documents_service:) }

  let(:attachment) do
    instance_double(
      SupportingEvidenceAttachment,
      guid: 'attachment-guid',
      converted_filename: nil
    )
  end
  let(:submission) do
    instance_double(
      Form526Submission,
      auth_headers: { 'va_eauth_pid' => '123456789' },
      form: {
        Form526Submission::FORM_526_UPLOADS => [{
          'confirmationCode' => 'attachment-guid',
          'name' => 'example.pdf',
          'attachmentId' => 'L014'
        }]
      }
    )
  end
  let(:upload) do
    instance_double(
      Lighthouse526DocumentUpload,
      id: 42,
      completed?: true,
      document_type: Lighthouse526DocumentUpload::VETERAN_UPLOAD_DOCUMENT_TYPE,
      form_attachment: attachment,
      form526_submission: submission,
      created_at: Time.zone.parse('2026-08-10T12:00:00Z'),
      lighthouse_processing_started_at: Time.zone.parse('2026-08-10T12:01:00Z'),
      lighthouse_processing_ended_at: Time.zone.parse('2026-08-10T12:05:00Z')
    )
  end
  let(:documents_service) { instance_double(BenefitsDocuments::Service) }
  let(:document) do
    {
      'documentUuid' => 'document-uuid',
      'currentVersionUuid' => 'version-uuid',
      'originalFileName' => 'example.pdf',
      'documentTypeLabel' => 'Birth Certificate',
      'uploadedDateTime' => '2026-08-10T12:04:00Z'
    }
  end

  describe '#resolve' do
    it 'resolves one recent document with the submitted filename' do
      stub_search([document])

      expect(resolver.resolve).to eq(
        'provider' => 'benefits_documents',
        'document_uuid' => 'document-uuid',
        'current_version_uuid' => 'version-uuid',
        'original_filename' => 'example.pdf'
      )
    end

    it 'does not select an older document with the same filename' do
      stub_search([document.merge('uploadedDateTime' => '2026-07-01T12:04:00Z')])

      expect { resolver.resolve }.to raise_error(described_class::NotReady, /No Documents match/)
    end

    it 'uses the submitted label to disambiguate recent filename matches' do
      other = document.merge('documentUuid' => 'other-uuid', 'documentTypeLabel' => 'Other Correspondence')
      stub_search([document, other])

      expect(resolver.resolve.fetch('document_uuid')).to eq('document-uuid')
    end

    it 'does not guess when recent matches remain ambiguous' do
      other = document.merge('documentUuid' => 'other-uuid')
      stub_search([document, other])

      expect { resolver.resolve }.to raise_error(described_class::AmbiguousMatch, /found 2/)
    end

    it 'requires both stable pointer identifiers' do
      stub_search([document.except('currentVersionUuid')])

      expect { resolver.resolve }.to raise_error(described_class::NotReady, /current version UUID/)
    end
  end

  describe '#download' do
    it 'downloads document bytes using the resolved document UUID' do
      allow(documents_service).to receive(:participant_documents_download).and_return(
        instance_double(Faraday::Response, body: '%PDF content')
      )

      content = resolver.download('document_uuid' => 'document-uuid')

      expect(content).to eq('%PDF content')
      expect(documents_service).to have_received(:participant_documents_download).with(
        document_uuid: 'document-uuid',
        participant_id: '123456789'
      )
    end

    it 'rejects a download response without document bytes' do
      allow(documents_service).to receive(:participant_documents_download).and_return(
        instance_double(Faraday::Response, body: {})
      )

      expect { resolver.download('document_uuid' => 'document-uuid') }
        .to raise_error(described_class::DownloadFailed, /download was empty/)
    end
  end

  def stub_search(documents)
    allow(documents_service).to receive(:participant_documents_search).and_return(
      instance_double(
        Faraday::Response,
        body: {
          'data' => { 'documents' => documents },
          'pagination' => { 'pageNumber' => 1, 'pageSize' => 100, 'totalPages' => 1 }
        }
      )
    )
  end
end
