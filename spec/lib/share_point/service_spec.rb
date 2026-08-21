# frozen_string_literal: true

require 'rails_helper'
require 'share_point/service'

# To re-record VCR cassettes, perform the following steps:
# 1. add the following to `test.local.yml`, retrieving values from AWS Param Store:
# ```yaml
# sharepoint:
#   mobile_survey_storage:
#     authentication_url: https://localhost:<portforward_1 - e.g. 8443>
#     sharepoint_graph_url: https://localhost:<portforward_2 - e.g. 8444>
#     client_id: <your_client_id>
#     client_secret: <your_client_secret>
#     drive_id: <your_drive_id>
#     site_id: <your_site_id>
#     tenant_id: <your_tenant_id>
#     verify_ssl: false
# ```
# 2. Start a local port forward to BOTH the SharePoint authentication and Graph API endpoints:
# ```bash
# $ aws ssm start-session \
#   --target <staging_fwdproxy id, e.g. i-0c8d6c0b043f5d1fd> \
#   --region us-gov-west-1 \
#   --document-name AWS-StartPortForwardingSessionToRemoteHost \
#   --parameters '{"host":["graph.microsoft.com"],"portNumber":["443"],"localPortNumber":["8444"]}'
# ```
# 3. delete existing cassettes to be re-recorded
# 4. Run the tests to re-record the VCR cassettes.
# 5. In newly recorded cassettes, replace token and other sensitve values not covered by vcr.rb (see diff)

RSpec.describe SharePoint::Service do
  let(:sharepoint_feature) { :mobile_survey_storage }
  let(:service) { described_class.new(sharepoint_feature:) }
  let(:csv_data) { "name,value\nfoo,bar\n" }
  let(:sharepoint_path) { 'DEV ONLY/test/Survey Responses/give_feedback' }
  let(:file_name) { 'test_run.csv' }

  # Helper method to modify the auth connection for recording VCR cassettes
  def modified_auth_connection(service)
    allow(service).to receive(:auth_connection).and_wrap_original do |original, *args|
      conn = original.call(*args)
      conn.headers['Host'] = 'login.microsoftonline.com'
      conn
    end
  end

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
    let(:auth_token_url) do
      "#{Settings.sharepoint.mobile_survey_storage.authentication_url}/" \
        "#{Settings.sharepoint.mobile_survey_storage.tenant_id}/oauth2/v2.0/token"
    end

    let(:upload_url_pattern) do
      %r{#{Regexp.escape(Settings.sharepoint.mobile_survey_storage.sharepoint_graph_url)}/v1.0/sites/.*/content\z}
    end

    context 'when sharepoint path and filename contain spaces' do
      it 'encodes each path segment and filename before upload' do
        response = instance_double(Faraday::Response, success?: true)
        expected_upload_path =
          "/v1.0/sites/#{Settings.sharepoint.mobile_survey_storage.site_id}" \
          "/drives/#{Settings.sharepoint.mobile_survey_storage.drive_id}" \
          '/root:/DEV%20ONLY/test/Survey%20Responses/give_feedback/test_run.csv:/content'

        expect(service).to receive(:upload_file)
          .with(
            csv_data,
            expected_upload_path,
            addl_headers: hash_including('Content-Type' => 'text/csv',
                                         'Content-Length' => csv_data.bytesize.to_s)
          )
          .and_return(response)
        expect(StatsD).to receive(:increment)
          .with('api.sharepoint.mobile_survey_storage.upload_csv.success')

        service.upload_csv(csv_data, sharepoint_path, file_name)
      end
    end

    context 'when the upload succeeds' do
      before do
        modified_auth_connection(service)
      end

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
        modified_auth_connection(service)
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
      before do
        stub_request(:post, auth_token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'test-token' }.to_json
          )

        stub_request(:put, upload_url_pattern)
          .to_return(
            status: 500,
            headers: { 'Content-Type' => 'application/json' },
            body: { error: { code: 'internalError', message: 'Upload failed' } }.to_json
          )
      end

      it 'returns a non-success response and increments the failure StatsD metric' do
        expect(StatsD).to receive(:increment)
          .with('api.sharepoint.mobile_survey_storage.upload_csv.fail')
        response = service.upload_csv(csv_data, sharepoint_path, file_name)
        expect(response.success?).to be false
      end
    end

    context 'when a connection error is raised during upload' do
      before do
        stub_request(:post, auth_token_url)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: { access_token: 'test-token' }.to_json
          )
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
