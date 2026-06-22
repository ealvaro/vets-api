# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../support/form1010cg_helpers/test_file_helpers'

RSpec.describe 'V0::Form1010CG::Attachments', type: :request do
  let(:endpoint) { 'http://localhost:3000/v0/form1010cg/attachments' }
  let(:headers) do
    {
      'ACCEPT' => 'application/json',
      'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
      'HTTP_X_KEY_INFLECTION' => 'camel'
    }
  end
  let(:vcr_options) do
    {
      record: :none,
      allow_unused_http_interactions: false,
      match_requests_on: %i[method host]
    }
  end

  after do
    Form1010cg::Attachment.delete_all
  end

  def make_upload_request_with(file_fixture_path, content_type)
    request_options = {
      headers:,
      params: {
        attachment: {
          file_data: Form1010cgHelpers::TestFileHelpers.create_test_uploaded_file(file_fixture_path, content_type)
        }
      }
    }

    post(endpoint, **request_options)
  end

  describe 'POST /v0/form1010cg/attachments' do
    after do
      Form1010cg::Attachment.delete_all
    end

    context 'with JPG' do
      let(:form_attachment_guid) { 'cdbaedd7-e268-49ed-b714-ec543fbb1fb8' }
      # Cache ID from VCR cassette - must match for S3 URL consistency
      let(:carrierwave_cache_id) { '1619206365-340201329057824-0002-6154' }

      before do
        # Stub CarrierWave cache_id to match VCR cassette URLs
        allow(CarrierWave).to receive(:generate_cache_id).and_return(carrierwave_cache_id)
        allow(SecureRandom).to receive(:uuid).and_return(form_attachment_guid)
      end

      it 'accepts a file upload' do
        store_vcr_options = vcr_options.merge(allow_unused_http_interactions: true)
        VCR.use_cassette "s3/object/put/#{form_attachment_guid}/doctors-note.jpg", store_vcr_options do
          make_upload_request_with('doctors-note.jpg', 'image/jpg')

          expect(response).to have_http_status(:ok)

          res_body = JSON.parse(response.body)

          expect(res_body['data']).to be_present
          expect(res_body['data']['type']).to eq 'form1010cg_attachments'
          expect(res_body['data']['id'].to_i).to be > 0
          expect(res_body['data']['attributes']['guid']).to eq form_attachment_guid
        end
      end
    end

    context 'with PDF' do
      let(:form_attachment_guid) { '834d9f51-d0c7-4dc2-9f2e-9b722db98069' }
      # Cache ID from VCR cassette - must match for S3 URL consistency
      let(:carrierwave_cache_id) { '1619206361-354509863784495-0001-7383' }

      before do
        # Stub CarrierWave cache_id to match VCR cassette URLs
        allow(CarrierWave).to receive(:generate_cache_id).and_return(carrierwave_cache_id)
        allow(SecureRandom).to receive(:uuid).and_return(form_attachment_guid)
      end

      it 'accepts a file upload' do
        store_vcr_options = vcr_options.merge(allow_unused_http_interactions: true)
        VCR.use_cassette "s3/object/put/#{form_attachment_guid}/doctors-note.pdf", store_vcr_options do
          make_upload_request_with('doctors-note.pdf', 'application/pdf')

          expect(response).to have_http_status(:ok)

          res_body = JSON.parse(response.body)

          expect(res_body['data']).to be_present
          expect(res_body['data']['type']).to eq 'form1010cg_attachments'
          expect(res_body['data']['id'].to_i).to be > 0
          expect(res_body['data']['attributes']['guid']).to eq form_attachment_guid
        end
      end
    end

    context 'with HEIC' do
      let(:form_attachment_guid) { '2fbd8c82-7754-4a96-81f2-b12b060a04a1' }
      let(:store_vcr_options) do
        vcr_options.merge(match_requests_on: %i[method host], allow_unused_http_interactions: true)
      end
      let(:heic_uppercase_file) do
        Rack::Test::UploadedFile.new(
          Rails.root.join('spec', 'fixtures', 'files', 'steelers.heic'),
          'image/heic',
          true,
          original_filename: 'steelers.HEIC'
        )
      end

      before do
        allow(SecureRandom).to receive(:uuid).and_return(form_attachment_guid)
        expect_any_instance_of(Form1010cg::PoaUploader)
          .to receive(:normalize_heic_to_jpg).at_least(:once).and_return(true)
      end

      it 'accepts a file upload with lowercase extension' do
        VCR.use_cassette('s3/object/put/cdbaedd7-e268-49ed-b714-ec543fbb1fb8/doctors-note.jpg', store_vcr_options) do
          make_upload_request_with('steelers.heic', 'image/heic')

          expect(response).to have_http_status(:ok)

          res_body = JSON.parse(response.body)

          expect(res_body['data']).to be_present
          expect(res_body['data']['type']).to eq 'form1010cg_attachments'
          expect(res_body['data']['id'].to_i).to be > 0
          expect(res_body['data']['attributes']['guid']).to eq form_attachment_guid
        end
      end

      it 'accepts a file upload with uppercase extension' do
        VCR.use_cassette('s3/object/put/cdbaedd7-e268-49ed-b714-ec543fbb1fb8/doctors-note.jpg', store_vcr_options) do
          post(
            endpoint,
            headers:,
            params: {
              attachment: {
                file_data: heic_uppercase_file
              }
            }
          )

          expect(response).to have_http_status(:ok)

          res_body = JSON.parse(response.body)

          expect(res_body['data']).to be_present
          expect(res_body['data']['type']).to eq 'form1010cg_attachments'
          expect(res_body['data']['id'].to_i).to be > 0
          expect(res_body['data']['attributes']['guid']).to eq form_attachment_guid
        end
      end
    end

    context 'with HEIF' do
      let(:form_attachment_guid) { 'ee3f562f-6de3-4558-a437-89feffb5827e' }
      let(:store_vcr_options) do
        vcr_options.merge(match_requests_on: %i[method host], allow_unused_http_interactions: true)
      end

      before do
        allow(SecureRandom).to receive(:uuid).and_return(form_attachment_guid)
        expect_any_instance_of(Form1010cg::PoaUploader)
          .to receive(:normalize_heic_to_jpg).at_least(:once).and_return(true)
      end

      it 'accepts a file upload' do
        VCR.use_cassette('s3/object/put/cdbaedd7-e268-49ed-b714-ec543fbb1fb8/doctors-note.jpg', store_vcr_options) do
          make_upload_request_with('steelers.heif', 'image/heif')

          expect(response).to have_http_status(:ok)

          res_body = JSON.parse(response.body)

          expect(res_body['data']).to be_present
          expect(res_body['data']['type']).to eq 'form1010cg_attachments'
          expect(res_body['data']['id'].to_i).to be > 0
          expect(res_body['data']['attributes']['guid']).to eq form_attachment_guid
        end
      end
    end

    context 'with unsupported file type' do
      it 'rejects the upload with a clear message' do
        make_upload_request_with('va.gif', 'image/gif')

        expect(response).to have_http_status(:unprocessable_entity)

        res_body = JSON.parse(response.body)
        error_detail = res_body.dig('errors', 0, 'detail')

        expect(error_detail).to include('You can’t upload "gif" files.')
        expect(error_detail).to include('The allowed file types are: jpg, jpeg, png, pdf, heic, heif')
      end
    end

    context 'when encrypted PDF cannot be decrypted' do
      it 'returns decryption error response in standard error format' do
        allow_any_instance_of(Form1010cg::Attachment).to receive(:set_file_data!).and_raise(
          Common::Exceptions::UnprocessableEntity.new(
            detail: I18n.t('errors.messages.uploads.pdf.incorrect_password'),
            source: 'Common::PdfHelpers.unlock_pdf'
          )
        )

        post(
          endpoint,
          headers:,
          params: {
            attachment: {
              file_data: Form1010cgHelpers::TestFileHelpers.create_test_uploaded_file(
                'doctors-note.pdf',
                'application/pdf'
              ),
              password: 'wrong-password'
            }
          }
        )

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to eq(
          {
            'errors' => [
              {
                'title' => 'Unprocessable Entity',
                'detail' => 'The password you entered is incorrect. Please try again.',
                'code' => '422',
                'source' => 'FormAttachment.unlock_pdf',
                'status' => '422'
              }
            ]
          }
        )
      end

      it 'returns standard error response for malformed or undecryptable PDF' do
        allow_any_instance_of(Form1010cg::Attachment).to receive(:set_file_data!).and_raise(
          Common::Exceptions::UnprocessableEntity.new(
            detail: I18n.t('errors.messages.uploads.pdf.invalid'),
            source: 'Common::PdfHelpers.unlock_pdf'
          )
        )

        post(
          endpoint,
          headers:,
          params: {
            attachment: {
              file_data: Form1010cgHelpers::TestFileHelpers.create_test_uploaded_file(
                'malformed-pdf.pdf',
                'application/pdf'
              ),
              password: 'some-password'
            }
          }
        )

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to eq(
          {
            'errors' => [
              {
                'title' => 'Unprocessable Entity',
                'detail' => 'The password you entered is incorrect. Please try again.',
                'code' => '422',
                'source' => 'FormAttachment.unlock_pdf',
                'status' => '422'
              }
            ]
          }
        )
      end
    end
  end
end
