# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/sidekiq/concerns/gclaws_xlsx_downloader'

RSpec.describe GCLAWSXlsxDownloader do
  let(:test_class) do
    Class.new do
      include GCLAWSXlsxDownloader

      attr_reader :errors

      def initialize
        @errors = []
      end

      def log_error(message)
        @errors << message
      end

      public :with_xlsx_file_content
    end
  end

  let(:instance) { test_class.new }
  let(:file_content) { 'binary xlsx content' }
  let(:temp_file) do
    f = Tempfile.new(['test', '.xlsx'])
    f.binmode
    f.write(file_content)
    f.close
    f
  end

  after do
    temp_file.unlink if File.exist?(temp_file.path)
  end

  describe '#with_xlsx_file_content' do
    context 'when source is gclaws' do
      context 'when download succeeds' do
        before do
          allow(RepresentationManagement::GCLAWS::XlsxClient)
            .to receive(:download_accreditation_xlsx)
            .and_yield({ success: true, file_path: temp_file.path })
        end

        it 'yields the binary file content to the block' do
          yielded = nil
          instance.with_xlsx_file_content { |content| yielded = content }

          expect(yielded).to eq(file_content)
        end
      end

      context 'when download fails' do
        before do
          allow(RepresentationManagement::GCLAWS::XlsxClient)
            .to receive(:download_accreditation_xlsx)
            .and_yield({ success: false, error: 'timeout', status: :request_timeout })
        end

        it 'does not yield to the block' do
          yielded = false

          expect { instance.with_xlsx_file_content { yielded = true } }
            .to raise_error(StandardError)

          expect(yielded).to be false
        end

        it 'logs the error and raises for Sidekiq retry' do
          expect { instance.with_xlsx_file_content { |_| } }
            .to raise_error(StandardError, /GCLAWS download failed: timeout/)

          expect(instance.errors).to include(
            'GCLAWS download failed: timeout (status: request_timeout)'
          )
        end
      end
    end

    context 'when source is sensitive_repo' do
      let(:fetcher) { instance_double(SensitiveRepoXlsxFileFetcher) }

      before do
        allow(SensitiveRepoXlsxFileFetcher).to receive(:new).and_return(fetcher)
      end

      context 'when fetch succeeds' do
        before do
          allow(fetcher).to receive(:fetch).and_return(file_content)
        end

        it 'yields the binary file content to the block' do
          yielded = nil
          instance.with_xlsx_file_content(source: 'sensitive_repo') { |content| yielded = content }

          expect(yielded).to eq(file_content)
        end
      end

      context 'when fetch returns nil' do
        before do
          allow(fetcher).to receive(:fetch).and_return(nil)
        end

        it 'does not yield to the block' do
          yielded = false

          expect { instance.with_xlsx_file_content(source: 'sensitive_repo') { yielded = true } }
            .to raise_error(StandardError)

          expect(yielded).to be false
        end

        it 'logs the error and raises' do
          expect { instance.with_xlsx_file_content(source: 'sensitive_repo') { |_| } }
            .to raise_error(StandardError, /Sensitive repo XLSX fetch failed or no fresh file was available/)

          expect(instance.errors).to include(
            'Sensitive repo XLSX fetch failed or no fresh file was available'
          )
        end
      end
    end

    context 'when source is unsupported' do
      it 'raises an ArgumentError' do
        expect { instance.with_xlsx_file_content(source: 'sensitive-repo') { |_| } }
          .to raise_error(ArgumentError, 'Unsupported XLSX source: sensitive-repo')
      end
    end
  end
end
