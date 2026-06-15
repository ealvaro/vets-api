# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SensitiveRepoXlsxFileFetcher do
  describe '#fetch' do
    let(:octokit_client) { instance_double(Octokit::Client) }
    let(:github_access_token) { 'test_token' }
    let(:file_info) do
      double(
        'Sawyer::Resource',
        download_url: 'https://example.com/file.xlsx'
      )
    end
    let(:commits) do
      [
        double(
          'commit',
          commit: double(
            'commit data',
            author: double('author', date: 1.hour.ago)
          )
        )
      ]
    end
    let(:fetcher) { described_class.new }
    let(:success_response) { instance_double(Faraday::Response, body: 'file content', success?: true) }

    before do
      allow(Rails.logger).to receive(:error)
      allow(Octokit::Client).to receive(:new).and_return(octokit_client)
      allow(octokit_client).to receive_messages(commits:, contents: file_info)
      allow(Settings.xlsx_file_fetcher).to receive(:github_access_token).and_return(github_access_token)
      allow(Faraday).to receive(:get).and_return(success_response)
    end

    context 'when fetching file successfully and it is recently updated' do
      it 'returns the content of the file' do
        expect(fetcher.fetch).to eq('file content')
      end

      it 'uses the configured timeouts' do
        request_options = nil

        allow(Faraday).to receive(:get) do |_url, &block|
          req = Struct.new(:options).new(Struct.new(:open_timeout, :timeout).new)
          block.call(req)
          request_options = req.options
          success_response
        end

        fetcher.fetch

        expect(request_options.open_timeout).to eq(described_class::OPEN_TIMEOUT)
        expect(request_options.timeout).to eq(described_class::READ_TIMEOUT)
      end
    end

    context 'when the GitHub token is blank' do
      before do
        allow(Settings.xlsx_file_fetcher).to receive(:github_access_token).and_return(nil)
      end

      it 'returns nil' do
        expect(fetcher.fetch).to be_nil
      end
    end

    context 'when an error occurs during fetching file info' do
      it 'handles the error and returns nil' do
        allow(octokit_client).to receive(:contents).and_raise(StandardError.new('test error'))

        expect { fetcher.fetch }.not_to raise_error
        expect(fetcher.fetch).to be_nil
      end
    end

    context 'when the file has not been updated in the last 24 hours' do
      let(:old_commits) do
        [
          double(
            'commit',
            commit: double(
              'commit data',
              author: double('author', date: 25.hours.ago)
            )
          )
        ]
      end

      it 'returns nil' do
        allow(octokit_client).to receive(:commits).and_return(old_commits)

        expect(fetcher.fetch).to be_nil
      end
    end

    context 'when the download URL is not https' do
      let(:file_info) do
        double(
          'Sawyer::Resource',
          download_url: 'http://example.com/file.xlsx'
        )
      end

      it 'returns nil' do
        expect(fetcher.fetch).to be_nil
      end
    end

    context 'when the download URL is invalid' do
      let(:file_info) do
        double(
          'Sawyer::Resource',
          download_url: 'not a valid url'
        )
      end

      it 'returns nil' do
        expect(fetcher.fetch).to be_nil
      end
    end

    context 'when the faraday response is not successful' do
      let(:error_response) { instance_double(Faraday::Response, status: 500, success?: false) }

      before do
        allow(Faraday).to receive(:get).and_return(error_response)
      end

      it 'returns nil' do
        expect(fetcher.fetch).to be_nil
      end
    end

    context 'when faraday raises an error' do
      before do
        allow(Faraday).to receive(:get).and_raise(Faraday::TimeoutError.new('execution expired'))
      end

      it 'returns nil' do
        expect(fetcher.fetch).to be_nil
      end
    end
  end
end
