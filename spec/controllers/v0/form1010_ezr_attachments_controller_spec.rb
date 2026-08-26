# frozen_string_literal: true

require 'rails_helper'
require 'support/1010_forms/shared_examples/form_attachment'

RSpec.describe V0::Form1010EzrAttachmentsController, type: :controller do
  shared_examples 'accepts HEIC/HEIF attachment' do |uploaded_file|
    it 'accepts the attachment' do
      post(:create, params: { 'form1010_ezr_attachment' => { 'file_data' => send(uploaded_file) } })

      response_body = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(response_body['data']['attributes']['guid']).to be_present
    end
  end

  let(:current_user) { build(:evss_user, :loa3, icn: '1013032368V065534') }
  let(:file) { fixture_file_upload('spec/fixtures/files/empty_file.txt', 'text/plain') }
  let(:heic_file) { fixture_file_upload('spec/fixtures/files/steelers.heic', 'image/heic') }
  let(:heif_file) { fixture_file_upload('spec/fixtures/files/steelers.heif', 'image/heif') }
  let(:heic_uppercase_file) do
    Rack::Test::UploadedFile.new(
      Rails.root.join('spec', 'fixtures', 'files', 'steelers.heic'),
      'image/heic',
      true,
      original_filename: 'steelers.HEIC'
    )
  end
  let(:params) { { 'form1010_ezr_attachment' => { 'file_data' => file } } }
  let(:unsupported_file_type_error_msg) do
    'File type not supported. Follow the instructions on your device ' \
      'on how to convert the file type and try again to continue.'
  end

  describe '::FORM_ATTACHMENT_MODEL' do
    it_behaves_like 'inherits the FormAttachment model'
  end

  describe '#create' do
    context 'unauthenticated' do
      it 'returns a 401' do
        post(:create, params:)

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include('Not authorized')
      end
    end

    context 'authenticated' do
      before do
        sign_in(current_user)
      end

      it_behaves_like 'create 1010 form attachment'

      context 'when uploading HEIC/HEIF attachments' do
        include_examples 'accepts HEIC/HEIF attachment', :heic_file
        include_examples 'accepts HEIC/HEIF attachment', :heif_file
        include_examples 'accepts HEIC/HEIF attachment', :heic_uppercase_file
      end
    end

    context 'image auto-resize' do
      let(:oversized_image) { fixture_file_upload('oversized-image.png', 'image/png') }
      let(:params) { { 'form1010_ezr_attachment' => { 'file_data' => oversized_image } } }

      before do
        sign_in(current_user)
      end

      context 'when hca_auto_resize_on_upload is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:hca_auto_resize_on_upload, anything).and_return(true)
        end

        it 'downscales the oversized image so the upload succeeds' do
          expect(Form1010EzrAttachments::ImageResizeService).to receive(:new).and_call_original

          post(:create, params:)

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)['data']['attributes']['guid']).to be_present
        end
      end

      context 'when hca_auto_resize_on_upload is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:hca_auto_resize_on_upload, anything).and_return(false)
        end

        it 'does not resize the image (regression: existing behavior unchanged)' do
          expect(Form1010EzrAttachments::ImageResizeService).not_to receive(:new)

          post(:create, params:)

          expect(response).to have_http_status(:ok)
        end
      end
    end

    context 'when the file type of the attachment is not valid in the Enrollment System' do
      before do
        sign_in(current_user)
      end

      context 'when an exception occurs' do
        before do
          allow(Rails.logger).to receive(:error)
          allow(IO).to receive(:popen).and_return(nil)
        end

        it 'increments StatsD and logs and raises an error' do
          allow(StatsD).to receive(:increment)
          expect(StatsD).to receive(:increment).with('api.1010ezr.attachments.failed')

          post(:create, params:)

          expect(Rails.logger).to have_received(:error).with(
            "Form1010EzrAttachment validate file type failed undefined method 'split' for nil.",
            backtrace: anything
          )

          error = JSON.parse(response.body)['errors'].first

          expect(response).to have_http_status(:internal_server_error)
          expect(error['title']).to eq('Internal server error')
          expect(error['code']).to eq('500')
        end
      end

      context 'when no exception occurs' do
        it 'increments StatsD and raises an error' do
          allow(StatsD).to receive(:increment)
          expect(StatsD).to receive(:increment).with('api.1010ezr.attachments.invalid_file_type')

          post(:create, params:)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)).to eq(
            {
              'errors' => [{
                'title' => 'Unprocessable Entity',
                'detail' => unsupported_file_type_error_msg,
                'code' => '422',
                'status' => '422'
              }]
            }
          )
        end
      end
    end
  end
end
