# frozen_string_literal: true

require 'rails_helper'
require 'sharepoint/service'

RSpec.describe SharePoint::Service, skip: 'recording cassettes' do
  let(:sharepoint_feature) { :mobile_survey_storage }
  let(:service) { described_class.new(sharepoint_feature:) }
  let(:csv_data) { "name,value\nfoo,bar\n" }
  let(:sharepoint_path) { 'surveys/test_folder' }
  let(:file_name) { 'survey_123.csv' }

  describe '#initialize' do
    context 'when settings exist for the given feature' do
      it 'initializes without error' do
        expect { service }.not_to raise_error
      end
    end

    context 'when no settings exist for the given feature' do
      it 'raises ArgumentError' do
        expect { described_class.new(sharepoint_feature: :nonexistent_feature) }
          .to raise_error(ArgumentError, /No SharePoint settings found for sharepoint_feature: nonexistent_feature/)
      end
    end
  end

  describe '#upload_csv' do
    context 'when the upload succeeds' do
      it 'returns a successful response and increments the success StatsD metric' do
        expect(StatsD).to receive(:increment)
          .with('api.sharepoint.mobile_survey_storage.upload_csv.success')
        VCR.use_cassette('sharepoint/upload_csv_success') do
          response = service.upload_csv(csv_data, sharepoint_path, file_name)
          expect(response.success?).to be true
        end
      end
    end

    context 'when authentication fails' do
      before do
        allow(Settings.sharepoint.mobile_survey_storage).to receive(:client_secret).and_return('invalid_secret')
      end

      it 'raises a SharePoint::AuthenticationError, increments the failure StatsD metric, and logs the error' do
        expect(StatsD).to receive(:increment)
          .with('api.sharepoint.mobile_survey_storage.upload_csv.fail')
        expect(Rails.logger).to receive(:error)
          .with('SharePoint CSV upload failed', hash_including(message: /SharePoint authentication failed/))
        VCR.use_cassette('sharepoint/upload_csv_unauthorized') do
          expect { service.upload_csv(csv_data, sharepoint_path, file_name) }
            .to raise_error(SharePoint::AuthenticationError, /SharePoint authentication failed/)
        end
      end
    end

    context 'when the Graph API upload fails' do
      it 'returns a non-success response and increments the failure StatsD metric' do
        expect(StatsD).to receive(:increment)
          .with('api.sharepoint.mobile_survey_storage.upload_csv.fail')
        VCR.use_cassette('sharepoint/upload_csv_upload_failed') do
          response = service.upload_csv(csv_data, sharepoint_path, file_name)
          expect(response.success?).to be false
        end
      end
    end

    context 'when a connection error is raised during upload' do
      let(:token_url) do
        "https://login.microsoftonline.com/#{Settings.sharepoint.mobile_survey_storage.tenant_id}/oauth2/v2.0/token"
      end

      before do
        stub_request(:post, token_url)
          .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                     body: { access_token: 'test-token' }.to_json)
        allow_any_instance_of(Faraday::Connection).to receive(:put)
          .and_raise(Faraday::ConnectionFailed.new('connection refused'))
      end

      it 're-raises the error' do
        allow(StatsD).to receive(:increment)
        expect { service.upload_csv(csv_data, sharepoint_path, file_name) }
          .to raise_error(Faraday::ConnectionFailed)
      end

      it 'increments the failure StatsD metric' do
        expect(StatsD).to receive(:increment)
          .with('api.sharepoint.mobile_survey_storage.upload_csv.fail')
        service.upload_csv(csv_data, sharepoint_path, file_name)
      rescue Faraday::ConnectionFailed
        nil
      end

      it 'logs the error' do
        allow(StatsD).to receive(:increment)
        expect(Rails.logger).to receive(:error)
          .with('SharePoint CSV upload failed', hash_including(message: anything))
        service.upload_csv(csv_data, sharepoint_path, file_name)
      rescue Faraday::ConnectionFailed
        nil
      end
    end
  end
end
