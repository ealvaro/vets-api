# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'V0::UploadSupportingEvidence', type: :request do
  include SchemaMatchers
  let(:user) { build(:disabilities_compensation_user) }

  let(:pdf_file) do
    fixture_file_upload('doctors-note.pdf', 'application/pdf')
  end

  let(:encrypted_pdf_file) do
    fixture_file_upload('password_is_test.pdf', 'application/pdf')
  end

  before do
    sign_in_as(user)
  end

  describe 'Post /v0/upload_supporting_evidence' do
    context 'with valid parameters' do
      it 'returns a 200 and an upload guid' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: pdf_file } }
        expect(response).to have_http_status(:ok)
        sea = SupportingEvidenceAttachment.last
        expect(JSON.parse(response.body)['data']['attributes']['guid']).to eq sea.guid
        expect(sea.get_file&.read).not_to be_nil
      end

      context 'when filename exceeds MAX_FILENAME_LENGTH' do
        let(:long_filename) { "#{'a' * 200}.pdf" }
        let(:long_filename_file) do
          file = fixture_file_upload('doctors-note.pdf', 'application/pdf')
          allow(file).to receive(:original_filename).and_return(long_filename)
          file
        end

        it 'stores the file with a shortened filename' do
          post '/v0/upload_supporting_evidence',
               params: { supporting_evidence_attachment: { file_data: long_filename_file } }
          expect(response).to have_http_status(:ok)
          sea = SupportingEvidenceAttachment.last
          stored_filename = sea.parsed_file_data['filename']
          expect(stored_filename.length).to be <= SupportingEvidenceAttachmentUploader::MAX_FILENAME_LENGTH
          expect(stored_filename).to end_with('.pdf')
        end

        it 'can retrieve the file without ENAMETOOLONG error' do
          post '/v0/upload_supporting_evidence',
               params: { supporting_evidence_attachment: { file_data: long_filename_file } }
          sea = SupportingEvidenceAttachment.last
          expect { sea.get_file }.not_to raise_error
          expect(sea.get_file&.read).not_to be_nil
        end
      end
    end

    context 'with valid encrypted parameters' do
      it 'returns a 200 and an upload guid' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: encrypted_pdf_file, password: 'test' } }
        expect(response).to have_http_status(:ok)
        sea = SupportingEvidenceAttachment.last
        expect(JSON.parse(response.body)['data']['attributes']['guid']).to eq sea.guid
        expect(sea.get_file&.read).not_to be_nil
      end

      it 'returns a 422 for a pdf with an incorrect password' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: encrypted_pdf_file, password: 'bad pwd' } }
        expect(response).to have_http_status(:unprocessable_entity)
        err = JSON.parse(response.body)['errors'][0]
        expect(err['title']).to eq 'Unprocessable Entity'
      end

      it 'returns a 200 for a pdf with a password that was not encrypted' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: pdf_file, password: 'unnecessary' } }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['data']['attributes']['guid']).to eq SupportingEvidenceAttachment.last.guid
      end

      it 'returns a 422 for a malformed pdf' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: fixture_file_upload('malformed-pdf.pdf') } }
        expect(response).to have_http_status(:unprocessable_entity)
        err = JSON.parse(response.body)['errors'][0]
        expect(err['title']).to eq 'Unprocessable Entity'
        expect(err['detail']).to eq I18n.t('errors.messages.uploads.pdf.invalid')
      end

      it 'returns a 422 for an unallowed file type' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment:
                       { file_data: fixture_file_upload('invalid_idme_cert.crt') } }
        expect(response).to have_http_status(:unprocessable_entity)
        err = JSON.parse(response.body)['errors'][0]
        expect(err['title']).to eq 'Unprocessable Entity'
        expect(err['detail']).to eq(
          I18n.t('errors.messages.extension_allowlist_error',
                 extension: '"crt"',
                 allowed_types: SupportingEvidenceAttachmentUploader.new('a').extension_allowlist.join(', '))
        )
      end

      it 'returns a 422 for a file that is too small' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment:
                       { file_data: fixture_file_upload('empty_file.txt') } }
        expect(response).to have_http_status(:unprocessable_entity)
        err = JSON.parse(response.body)['errors'][0]
        expect(err['title']).to eq 'Unprocessable Entity'
        expect(err['detail']).to eq(I18n.t('errors.messages.min_size_error', min_size: '1 Byte'))
      end
    end

    context 'with invalid parameters' do
      it 'returns a 400 with no parameters' do
        post '/v0/upload_supporting_evidence', params: nil
        expect(response).to have_http_status(:bad_request)
      end

      it 'returns a 400 with no file_data' do
        post '/v0/upload_supporting_evidence', params: { supporting_evidence_attachment: {} }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'with attachment_id parameter and validation enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:disability_526_document_validation_enabled, instance_of(User))
          .and_return(true)
      end

      it 'returns empty warnings array when document matches' do
        allow_any_instance_of(RTesseract).to receive(:to_s)
          .and_return('Separation Health Assessment - Part A: Veteran Information')

        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: pdf_file, attachment_id: 'L1839' } }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'attributes', 'warnings')).to eq([])
      end

      it 'returns wrong_form warning when document does not match expected form' do
        allow_any_instance_of(RTesseract).to receive(:to_s)
          .and_return('Random unrelated document text')

        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: pdf_file, attachment_id: 'L1839' } }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'attributes', 'warnings')).to eq(['wrong_form'])
      end

      it 'returns unable_to_validate warning when OCR fails' do
        allow_any_instance_of(RTesseract).to receive(:to_s).and_raise(RuntimeError, 'OCR failure')

        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: pdf_file, attachment_id: 'L1839' } }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'attributes', 'warnings')).to eq(['unable_to_validate'])
      end

      it 'does not include warnings when attachment_id is not provided' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: pdf_file } }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'attributes', 'warnings')).to be_nil
      end
    end

    context 'with attachment_id parameter and validation disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:disability_526_document_validation_enabled, instance_of(User))
          .and_return(false)
      end

      it 'does not include warnings even when attachment_id is provided' do
        post '/v0/upload_supporting_evidence',
             params: { supporting_evidence_attachment: { file_data: pdf_file, attachment_id: 'L1839' } }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('data', 'attributes', 'warnings')).to be_nil
      end
    end
  end
end
