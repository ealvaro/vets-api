# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MyHealth::V2::ImagingStreamingController', :skip_json_api_validation, type: :request do
  let(:path) { '/my_health/v2/medical_records/imaging/thumbnail_proxy_stream' }
  let(:current_user) { build(:user, :mhv) }
  let(:valid_s3_url) do
    'https://mhv-sysb-cvix-thumbnails.s3.us-gov-west-1.amazonaws.com/hashed-abc123/thumb.jpg' \
      '?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Expires=1800&X-Amz-Signature=abc123'
  end
  let(:image_binary) { "\xFF\xD8\xFF\xE0".b + ('x' * 100) }

  before do
    sign_in_as(current_user, stub_mhv_account: true)
    allow_any_instance_of(User).to receive(:va_treatment_facility_ids).and_return([])
    allow_any_instance_of(User).to receive(:cerner_facility_ids).and_return(%w[668])
  end

  describe 'GET /my_health/v2/medical_records/imaging/thumbnail_proxy_stream' do
    context 'happy path' do
      it 'streams the image from S3 and returns JPEG binary' do
        stub_request(:get, /mhv-sysb-cvix-thumbnails\.s3\.us-gov-west-1\.amazonaws\.com/)
          .to_return(status: 200, body: image_binary, headers: { 'Content-Type' => 'image/jpeg' })

        get path, params: { url: valid_s3_url }

        expect(response).to be_successful
        expect(response.headers['Content-Type']).to include('image/jpeg')
        expect(response.body.bytes).to eq(image_binary.bytes)
      end
    end

    context 'when url param is missing' do
      it 'returns a 400 error' do
        get path

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when URL host is not an allowed S3 domain' do
      it 'returns a 403 error for non-S3 hosts' do
        get path, params: { url: 'https://evil-site.com/malicious.jpg' }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['errors']).to be_an(Array)
        expect(json['errors'].first).to include('detail' => 'URL not allowed')
      end

      it 'returns a 403 error for non-HTTPS URLs' do
        get path, params: { url: 'http://mhv-sysb-cvix-thumbnails.s3.us-gov-west-1.amazonaws.com/thumb.jpg' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when URL is malformed' do
      it 'returns a 400 error' do
        get path, params: { url: ':::not-a-url' }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when S3 returns a non-success response' do
      it 'returns an error for 404' do
        stub_request(:get, /mhv-sysb-cvix-thumbnails\.s3\.us-gov-west-1\.amazonaws\.com/)
          .to_return(status: 404, body: 'Not Found')

        get path, params: { url: valid_s3_url }

        expect(response).not_to be_successful
      end

      it 'returns an error for 500' do
        stub_request(:get, /mhv-sysb-cvix-thumbnails\.s3\.us-gov-west-1\.amazonaws\.com/)
          .to_return(status: 500, body: 'Internal Server Error')

        get path, params: { url: valid_s3_url }

        expect(response).not_to be_successful
      end
    end

    context 'when S3 host uses dash-style region format' do
      let(:dash_style_url) do
        'https://mhv-pr-cvix-thumbnails.s3-us-gov-west-1.amazonaws.com/thumb.jpg?X-Amz-Signature=abc'
      end

      it 'accepts the URL and streams successfully' do
        stub_request(:get, /mhv-pr-cvix-thumbnails\.s3-us-gov-west-1\.amazonaws\.com/)
          .to_return(status: 200, body: image_binary, headers: { 'Content-Type' => 'image/jpeg' })

        get path, params: { url: dash_style_url }

        expect(response).to be_successful
        expect(response.headers['Content-Type']).to include('image/jpeg')
      end
    end

    context 'when S3 bucket name is not in the allowlist' do
      it 'returns a 403 error for unknown bucket names' do
        get path, params: {
          url: 'https://some-other-bucket.s3.us-gov-west-1.amazonaws.com/thumb.jpg'
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with each allowed environment bucket' do
      %w[di-5 intb sysb pr].each do |env|
        it "accepts mhv-#{env}-cvix-thumbnails bucket" do
          bucket_url = "https://mhv-#{env}-cvix-thumbnails.s3.us-gov-west-1.amazonaws.com/thumb.jpg?X-Amz-Signature=abc"
          stub_request(:get, /mhv-#{Regexp.escape(env)}-cvix-thumbnails/)
            .to_return(status: 200, body: image_binary, headers: { 'Content-Type' => 'image/jpeg' })

          get path, params: { url: bucket_url }

          expect(response).to be_successful
        end
      end
    end

    context 'sets streaming-appropriate response headers' do
      it 'includes Cache-Control header' do
        stub_request(:get, /mhv-sysb-cvix-thumbnails\.s3\.us-gov-west-1\.amazonaws\.com/)
          .to_return(status: 200, body: image_binary, headers: { 'Content-Type' => 'image/jpeg' })

        get path, params: { url: valid_s3_url }

        expect(response).to be_successful
        expect(response.headers['Cache-Control']).to include('private')
      end
    end
  end
end
