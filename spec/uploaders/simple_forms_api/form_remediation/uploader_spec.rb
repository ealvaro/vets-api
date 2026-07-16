# frozen_string_literal: true

require 'rails_helper'
require SimpleFormsApi::Engine.root.join('spec', 'spec_helper.rb')
require 'simple_forms_api/form_remediation/configuration/vff_config'

RSpec.describe SimpleFormsApi::FormRemediation::Uploader do
  let(:config) do
    instance_double(
      SimpleFormsApi::FormRemediation::Configuration::VffConfig,
      s3_settings: OpenStruct.new(region: 'region', bucket: bucket_name),
      handle_error: nil
    )
  end
  let(:directory)   { '/some/path' }
  let(:bucket_name) { 'bucket' }
  let(:uploader_instance) { described_class.new(directory:, config:) }

  before do
    allow(Rails.logger).to receive(:error).and_call_original
    allow(Rails.logger).to receive(:info).and_call_original
  end

  describe '#initialize' do
    subject(:new) { uploader_instance }

    it 'uses an AWS store', skip: 'TODO: Fix Flaky Test' do
      expect(described_class.storage).to eq(CarrierWave::Storage::AWS)
      expect(new._storage?).to be(true)
      expect(new._storage).to eq(CarrierWave::Storage::AWS)
    end

    it 'sets aws config' do
      expect(new.aws_acl).to eq('private')
      expect(new.aws_bucket).to eq(bucket_name)
      expect(new.aws_attributes).to eq(server_side_encryption: 'AES256')
      expect(new.aws_credentials).to eq(region: 'region')
    end

    context 'when config is nil' do
      let(:config) { nil }

      it 'throws an error' do
        expect { new }.to raise_exception(RuntimeError, a_string_including('The configuration is missing.'))
      end
    end

    context 'when directory is nil' do
      let(:directory) { nil }

      it 'throws an error' do
        expect { new }.to raise_exception(RuntimeError, a_string_including('The S3 directory is missing.'))
      end
    end
  end

  describe '#size_range' do
    subject(:size_range) { uploader_instance.size_range }

    it 'returns a range from 1 byte to 150 megabytes' do
      expect(size_range).to eq((1.byte)...(150.megabytes))
    end
  end

  describe '#extension_allowlist' do
    subject(:extension_allowlist) { uploader_instance.extension_allowlist }

    it 'allows image, pdf, json, csv, and text files' do
      expect(extension_allowlist).to match_array %w[bmp csv gif jpeg jpg json pdf png tif tiff txt zip]
    end
  end

  describe '#store_dir' do
    subject(:store_dir) { uploader_instance.store_dir }

    it 'returns a store directory containing the given directory' do
      expect(store_dir).to eq(directory)
    end
  end

  describe '#store!' do
    subject(:store!) { uploader_instance.store!(file) }

    let(:file) { instance_double(CarrierWave::SanitizedFile, filename: 'test_file.pdf', path: '/tmp/test_file.pdf') }

    before { allow(config).to receive(:handle_error) }

    context 'when the file is nil' do
      let(:file) { nil }

      it 'delegates to config.handle_error' do
        store!
        expect(config).to have_received(:handle_error).with(
          'An error occurred while uploading the file.',
          an_instance_of(RuntimeError)
        )
      end
    end

    context 'when the file does not respond to #filename' do
      let(:file) { 'not-a-file-object' }

      it 'delegates to config.handle_error' do
        store!
        expect(config).to have_received(:handle_error).with(
          'An error occurred while uploading the file.',
          an_instance_of(RuntimeError)
        )
      end
    end

    context 'when the file is valid and the upload succeeds' do
      before do
        allow_any_instance_of(CarrierWave::Uploader::Base).to receive(:store!).and_return(true)
      end

      it 'does not enqueue a retry job' do
        expect(SimpleFormsApi::FormRemediation::UploadRetryJob).not_to receive(:perform_async)
        store!
      end

      it 'does not create a temp copy' do
        expect(FileUtils).not_to receive(:cp)
        store!
      end
    end

    context 'when an aws service error occurs' do
      let(:aws_service_error) { Aws::S3::Errors::ServiceError.new(nil, 'Service error') }
      let(:expected_temp_dir)  { File.join(Dir.tmpdir, described_class::RETRY_TEMP_DIR) }
      let(:expected_temp_path) { File.join(expected_temp_dir, 'test-uuid_test_file.pdf') }

      before do
        allow_any_instance_of(CarrierWave::Uploader::Base).to receive(:store!).and_raise(aws_service_error)
        allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:cp)
        allow(SimpleFormsApi::FormRemediation::UploadRetryJob).to receive(:perform_async)
      end

      it 'does not raise' do
        expect { store! }.not_to raise_error
      end

      it 'returns false so callers know the upload was deferred' do
        expect(store!).to be false
      end

      it 'copies the file to the retry temp directory before enqueuing' do
        store!
        expect(FileUtils).to have_received(:mkdir_p).with(expected_temp_dir)
        expect(FileUtils).to have_received(:cp).with(file.path, expected_temp_path)
      end

      it 'enqueues UploadRetryJob with the temp path, not the original file path' do
        store!
        expect(SimpleFormsApi::FormRemediation::UploadRetryJob).to(
          have_received(:perform_async).with(expected_temp_path, directory, config.class.name)
        )
      end

      it 'logs the failure at error level including the directory' do
        store!
        expect(Rails.logger).to(
          have_received(:error).with(
            "SimpleFormsApi::FormRemediation::Uploader - upload failed, enqueuing retry for #{file.filename}",
            hash_including(directory:)
          )
        )
      end
    end

    context 'when a non-S3 RuntimeError occurs' do
      let(:runtime_error) { RuntimeError.new('unexpected problem') }

      before do
        allow_any_instance_of(CarrierWave::Uploader::Base).to receive(:store!).and_raise(runtime_error)
      end

      it 'delegates to config.handle_error' do
        store!
        expect(config).to have_received(:handle_error).with(
          'An error occurred while uploading the file.',
          runtime_error
        )
      end

      it 'does not enqueue a retry job' do
        expect(SimpleFormsApi::FormRemediation::UploadRetryJob).not_to receive(:perform_async)
        store!
      end
    end
  end

  describe '#store_for_retry!' do
    subject(:store_for_retry!) { uploader_instance.store_for_retry!(file) }

    let(:file) { instance_double(CarrierWave::SanitizedFile, filename: 'test_file.pdf', path: '/tmp/test_file.pdf') }

    context 'when the file is nil' do
      let(:file) { nil }

      it 'raises a RuntimeError' do
        expect { store_for_retry! }.to raise_error(RuntimeError, /Invalid file object/)
      end
    end

    context 'when the file is valid and upload succeeds' do
      before do
        allow_any_instance_of(CarrierWave::Uploader::Base).to receive(:store!).and_return(true)
      end

      it 'does not enqueue a retry job' do
        expect(SimpleFormsApi::FormRemediation::UploadRetryJob).not_to receive(:perform_async)
        store_for_retry!
      end
    end

    context 'when an S3 error occurs' do
      let(:aws_service_error) { Aws::S3::Errors::ServiceError.new(nil, 'Service error') }

      before do
        allow_any_instance_of(CarrierWave::Uploader::Base).to receive(:store!).and_raise(aws_service_error)
      end

      it 'propagates the error rather than rescuing it' do
        expect { store_for_retry! }.to raise_error(Aws::S3::Errors::ServiceError)
      end

      it 'does not enqueue a retry job' do
        expect(SimpleFormsApi::FormRemediation::UploadRetryJob).not_to receive(:perform_async)
        expect { store_for_retry! }.to raise_error(Aws::S3::Errors::ServiceError)
      end
    end

    context 'when the file is a non-nil invalid object' do
      let(:file) { 'not a file object' }

      it 'raises a RuntimeError' do
        expect { store_for_retry! }.to raise_error(RuntimeError, /Invalid file object/)
      end
    end
  end

  describe '#s3_exists?' do
    subject(:s3_exists?) { uploader_instance.s3_exists?(file_path) }

    let(:file_path) { 'submission/5.15.26-Form21P-601/test.pdf' }
    let(:s3_object) { instance_double(Aws::S3::Object) }

    before do
      allow(Aws::S3::Client).to receive(:new).and_return(instance_double(Aws::S3::Client))
      allow(Aws::S3::Resource).to receive(:new).and_return(
        instance_double(Aws::S3::Resource, bucket: instance_double(Aws::S3::Bucket, object: s3_object))
      )
    end

    context 'when the object exists' do
      before { allow(s3_object).to receive(:exists?).and_return(true) }

      it { is_expected.to be(true) }
    end

    context 'when the object does not exist' do
      before { allow(s3_object).to receive(:exists?).and_raise(Aws::S3::Errors::NotFound.new(nil, 'not found')) }

      it { is_expected.to be(false) }
    end

    context 'when the object raises NoSuchKey' do
      before { allow(s3_object).to receive(:exists?).and_raise(Aws::S3::Errors::NoSuchKey.new(nil, 'no key')) }

      it { is_expected.to be(false) }
    end

    context 'when a transient AWS error occurs' do
      let(:error) { Aws::S3::Errors::ServiceError.new(nil, 'timeout') }

      before { allow(s3_object).to receive(:exists?).and_raise(error) }

      it 'delegates to config.handle_error' do
        s3_exists?
        expect(config).to have_received(:handle_error).with('An error occurred while checking the file.', error)
      end
    end
  end
end
