# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SensitiveRepoCsvFileFetcher do
  subject { described_class.new }

  let(:github_token) { 'fake_github_token' }
  let(:token_generator) { instance_double(Github::InstallationTokenGenerator, generate: github_token) }
  let(:csv_content) do
    "Number,LastName,FirstName,MiddleName,WorkAddress1,WorkCity,WorkState,WorkZip,WorkNumber,WorkEmailAddress\n" \
      "102,Abel,Jami,Marie,105 Main Street,Painesville,OH,44077,440-350-2591,jami.abel@example.gov\n"
  end
  let(:download_url) { 'https://api.va.ghe.com/raw/file.csv' }
  let(:file_info) { double('FileInfo', download_url:) }
  let(:octokit_client) { instance_double(Octokit::Client) }

  before do
    allow(Settings.xlsx_file_fetcher.github_app).to receive_messages(
      app_id: 'fake_app_id',
      private_key: 'fake_private_key',
      org: 'software',
      repo: 'software/va.gov-team-sensitive',
      base_uri: 'https://api.va.ghe.com'
    )
    allow(Github::InstallationTokenGenerator).to receive(:new).and_return(token_generator)
    allow(Octokit::Client).to receive(:new).and_return(octokit_client)
    allow(octokit_client).to receive(:contents).and_return(file_info)
  end

  describe '#fetch' do
    context 'when the CSV file is fetched and parsed successfully' do
      before do
        stub_request(:get, download_url)
          .to_return(status: 200, body: csv_content)
      end

      it 'returns parsed CSV rows with headers' do
        rows = subject.fetch

        expect(rows).to be_a(CSV::Table)
        expect(rows.length).to eq(1)
        expect(rows.first['Number']).to eq('102')
        expect(rows.first['LastName']).to eq('Abel')
        expect(rows.first['FirstName']).to eq('Jami')
        expect(rows.first['WorkEmailAddress']).to eq('jami.abel@example.gov')
      end
    end

    context 'when the GitHub app configuration is invalid' do
      before do
        allow(Settings.xlsx_file_fetcher.github_app).to receive(:app_id).and_return('')
      end

      it 'returns nil and logs an error' do
        expect(Rails.logger).to receive(:error).with(
          /SensitiveRepoCsvFileFetcher error:.*GitHub app_id is missing/
        )

        expect(subject.fetch).to be_nil
      end
    end

    context 'when the file is not found in the GHE repo' do
      before do
        allow(octokit_client).to receive(:contents)
          .and_raise(Octokit::NotFound.new(method: 'GET', url: 'fake'))
      end

      it 'returns nil and logs an error' do
        expect(Rails.logger).to receive(:error).with(
          /SensitiveRepoCsvFileFetcher error:.*GET fake/
        )

        expect(subject.fetch).to be_nil
      end
    end

    context 'when the file download fails' do
      before do
        stub_request(:get, download_url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns nil and logs the error' do
        expect(Rails.logger).to receive(:error).with(
          /SensitiveRepoCsvFileFetcher error:.*Unexpected response downloading CSV file: 500/
        )

        expect(subject.fetch).to be_nil
      end
    end

    context 'when the CSV file is empty (headers only)' do
      let(:empty_csv) { "Number,LastName,FirstName\n" }

      before do
        stub_request(:get, download_url)
          .to_return(status: 200, body: empty_csv)
      end

      it 'returns an empty table' do
        rows = subject.fetch

        expect(rows).to be_a(CSV::Table)
        expect(rows).to be_empty
      end
    end

    context 'when a Faraday error occurs during download' do
      before do
        stub_request(:get, download_url)
          .to_raise(Faraday::ConnectionFailed.new('connection refused'))
      end

      it 'returns nil and logs the error' do
        expect(Rails.logger).to receive(:error).with(
          /SensitiveRepoCsvFileFetcher error:.*Error downloading CSV file/
        )

        expect(subject.fetch).to be_nil
      end
    end
  end
end
