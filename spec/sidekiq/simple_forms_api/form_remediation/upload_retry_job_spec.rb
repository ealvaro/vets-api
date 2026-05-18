# frozen_string_literal: true

require 'rails_helper'
require 'simple_forms_api/form_remediation/configuration/vff_config'

RSpec.describe SimpleFormsApi::FormRemediation::UploadRetryJob, type: :worker do
  let(:temp_dir)  { File.join(Dir.tmpdir, SimpleFormsApi::FormRemediation::Uploader::RETRY_TEMP_DIR) }
  let(:temp_path) { File.join(temp_dir, 'test-uuid_test_file.pdf') }
  let(:directory) { 'test/directory' }
  let(:s3_settings) { OpenStruct.new(region: 'us-east-1') }
  let(:config) do
    instance_double(SimpleFormsApi::FormRemediation::Configuration::VffConfig, uploader_class:, s3_settings:)
  end
  let(:uploader_class) { class_double(SimpleFormsApi::FormRemediation::Uploader) }
  let(:uploader_instance) { instance_double(SimpleFormsApi::FormRemediation::Uploader) }
  let(:s3_client_instance) { instance_double(Aws::S3::Client) }

  before do
    allow(uploader_class).to receive(:new).with(directory:, config:).and_return(uploader_instance)
    allow(StatsD).to receive(:increment)
    allow(Aws::S3::Client).to receive(:new).and_return(s3_client_instance)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(File).to receive(:exist?).and_call_original
  end

  # Helper: create a real temp file so File.exist? and FileUtils.rm_f work correctly
  def with_temp_file(path)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.touch(path)
    yield
  ensure
    FileUtils.rm_f(path)
  end

  describe '#perform' do
    context 'when the upload succeeds' do
      before { allow(uploader_instance).to receive(:store_for_retry!) }

      it 'uploads the file and increments the StatsD counters' do
        with_temp_file(temp_path) do
          described_class.new.perform(temp_path, directory, config)

          expect(uploader_instance).to have_received(:store_for_retry!)

          expect(StatsD).to have_received(:increment).with('api.simple_forms_api.upload_retry_job.total')
          expect(StatsD).to have_received(:increment).with('api.simple_forms_api.upload_retry_job.success')
        end
      end

      it 'deletes the temp file after a successful upload' do
        with_temp_file(temp_path) do
          described_class.new.perform(temp_path, directory, config)
          expect(File.exist?(temp_path)).to be false
        end
      end
    end

    context 'when arguments are strings (Sidekiq serialization)' do
      let(:config_string) { 'SimpleFormsApi::FormRemediation::Configuration::VffConfig' }
      let(:resolved_config) do
        instance_double(SimpleFormsApi::FormRemediation::Configuration::VffConfig, uploader_class:, s3_settings:)
      end

      before do
        allow(SimpleFormsApi::FormRemediation::Configuration::VffConfig).to receive(:new).and_return(resolved_config)
        allow(uploader_class).to receive(:new).with(directory:, config: resolved_config).and_return(uploader_instance)
        allow(uploader_instance).to receive(:store_for_retry!)
      end

      it 'converts strings back to their proper types and uploads successfully' do
        with_temp_file(temp_path) do
          described_class.new.perform(temp_path, directory, config_string)

          expect(SimpleFormsApi::FormRemediation::Configuration::VffConfig).to have_received(:new)
          expect(uploader_instance).to have_received(:store_for_retry!).with(an_instance_of(CarrierWave::SanitizedFile))

          expect(StatsD).to have_received(:increment).with('api.simple_forms_api.upload_retry_job.total')
        end
      end
    end

    context 'when the file no longer exists on disk' do
      before { allow(File).to receive(:exist?).with(temp_path).and_return(false) }

      it 'raises a FileNoLongerExistsError and increments the file_missing StatsD counter' do
        expect do
          described_class.new.perform(temp_path, directory, config)
        end.to raise_error(described_class::FileNoLongerExistsError, /Retry file no longer exists/)

        expect(StatsD).to have_received(:increment).with('api.simple_forms_api.upload_retry_job.file_missing')
      end

      it 'does not attempt the upload' do
        allow(uploader_instance).to receive(:store!)

        begin
          described_class.new.perform(temp_path, directory, config)
        rescue described_class::FileNoLongerExistsError
          nil
        end

        allow(uploader_instance).to receive(:store_for_retry!)
        expect(uploader_instance).not_to have_received(:store_for_retry!)
      end
    end

    context 'when the upload fails with a ServiceError' do
      before do
        allow(uploader_instance).to receive(:store_for_retry!)
          .and_raise(Aws::S3::Errors::ServiceError.new(nil,
                                                       'Service error'))
      end

      context 'and the service is available' do
        before { allow(s3_client_instance).to receive(:list_buckets).and_return(true) }

        it 'raises the error so Sidekiq retries normally' do
          with_temp_file(temp_path) do
            expect do
              described_class.new.perform(temp_path, directory, config)
            end.to raise_error(Aws::S3::Errors::ServiceError)

            expect(StatsD).to have_received(:increment).with('api.simple_forms_api.upload_retry_job.total')
          end
        end

        it 'does not delete the temp file so the next Sidekiq retry can use it' do
          with_temp_file(temp_path) do
            begin
              described_class.new.perform(temp_path, directory, config)
            rescue
              nil
            end
            expect(File.exist?(temp_path)).to be true
          end
        end
      end

      context 'and the service is unavailable' do
        before do
          allow(s3_client_instance).to(
            receive(:list_buckets).and_raise(Aws::S3::Errors::ServiceError.new(nil, 'Service error'))
          )
          allow(described_class).to receive(:perform_in)
        end

        it 'enqueues a delayed retry with the temp path and logs the deferral' do
          with_temp_file(temp_path) do
            described_class.new.perform(temp_path, directory, config)

            expect(described_class).to have_received(:perform_in).with(
              anything, temp_path, directory, config.class.name
            )
            expect(Rails.logger).to have_received(:info).with(
              'SimpleFormsApi::FormRemediation::UploadRetryJob - S3 service unavailable, scheduling retry',
              hash_including(temp_path:, s3_directory: directory)
            )
          end
        end

        it 'does not delete the temp file' do
          with_temp_file(temp_path) do
            described_class.new.perform(temp_path, directory, config)
            expect(File.exist?(temp_path)).to be true
          end
        end
      end
    end
  end

  describe 'sidekiq_retry_in' do
    it 'returns :kill for FileNoLongerExistsError to skip retries' do
      job = described_class.new
      exception = described_class::FileNoLongerExistsError.new('file gone')

      result = job.sidekiq_retry_in_block.call(0, exception)

      expect(result).to eq(:kill)
    end

    it 'returns nil for other errors to use default retry timing' do
      job = described_class.new
      exception = Aws::S3::Errors::ServiceError.new(nil, 'Service error')

      result = job.sidekiq_retry_in_block.call(0, exception)

      expect(result).to be_nil
    end
  end

  describe 'sidekiq_retries_exhausted' do
    let(:exception) { Aws::S3::Errors::ServiceError.new(%w[backtrace1 backtrace2], 'Service error') }
    let(:msg)       { { 'args' => [temp_path, directory, 'SimpleFormsApi::FormRemediation::Configuration::VffConfig'] } }

    it 'increments the retries_exhausted StatsD counter with the s3_directory tag' do
      described_class.new.sidekiq_retries_exhausted_block.call(msg, exception)

      expect(StatsD).to have_received(:increment).with(
        'api.simple_forms_api.upload_retry_job.retries_exhausted'
      )
    end

    it 'logs the error with temp_path and s3_directory for manual remediation' do
      described_class.new.sidekiq_retries_exhausted_block.call(msg, exception)

      expect(Rails.logger).to have_received(:error).with(
        a_string_including('manual remediation required'),
        hash_including(
          temp_path:,
          s3_directory: directory,
          exception:
        )
      )
    end
  end

  describe '#cleanup_temp_file! (private)' do
    it 'logs a warning instead of raising when the temp file is already gone' do
      job = described_class.new
      sanitized = CarrierWave::SanitizedFile.new('/nonexistent/already_gone.pdf')
      job.instance_variable_set(:@file, sanitized)

      expect { job.send(:cleanup_temp_file!) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(
        a_string_including('temp file already gone at cleanup'),
        hash_including(temp_path: '/nonexistent/already_gone.pdf')
      )
    end
  end
end
