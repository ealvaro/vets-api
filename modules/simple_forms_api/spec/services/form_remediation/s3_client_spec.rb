# frozen_string_literal: true

require 'rails_helper'
require SimpleFormsApi::Engine.root.join('spec', 'spec_helper.rb')
require 'simple_forms_api/form_remediation/error'
require 'simple_forms_api/form_remediation/configuration/vff_config'

RSpec.describe SimpleFormsApi::FormRemediation::S3Client do
  include SimpleFormsApi::FormRemediation::FileUtilities

  # Initial form data setup
  let(:form_type) { '20-10207' }
  let(:fixtures_path) { 'modules/simple_forms_api/spec/fixtures' }
  let(:form_data) do
    Rails.root.join(fixtures_path, 'form_json', 'vba_20_10207_with_supporting_documents.json').read
  end

  # Params setup
  let(:attachments) { Array.new(5) { Rails.root.join(fixtures_path, 'doctors-note.pdf') } }
  let(:submission) { create(:form_submission, :pending, form_type:, form_data:) }
  let(:benefits_intake_uuid) { submission.latest_attempt.benefits_intake_uuid }
  let(:config) { SimpleFormsApi::FormRemediation::Configuration::VffConfig.new }
  let(:file_path) { Rails.root.join(fixtures_path, 'pdfs', 'vba_20_10207-completed.pdf') }
  let(:metadata) do
    {
      'veteranFirstName' => 'John',
      'veteranLastName' => 'Veteran',
      'fileNumber' => '222773333',
      'zipCode' => '12345',
      'source' => 'VA Platform Digital Forms',
      'docType' => form_type,
      'businessLine' => 'CMP'
    }
  end
  let(:default_args) { { id: benefits_intake_uuid, config:, type: } }
  let(:hydrated_submission_args) { default_args.merge(submission:, file_path:, attachments:, metadata:) }

  # Mock file paths
  let(:submission_file_name) { unique_file_name(form_type, benefits_intake_uuid) }
  let(:s3_archive_dir) { "#{type}/#{dated_directory_name(form_type)}" }
  let(:s3_archive_path) { "#{s3_archive_dir}/#{submission_file_name}.#{type == :remediation ? 'zip' : 'pdf'}" }
  let(:local_archive_dir) { Rails.root.join('tmp', 'random-letters-n-numbers-archive').to_s }
  let(:local_archive_path) do
    "#{local_archive_dir}/#{submission_file_name}.#{type == :remediation ? 'zip' : 'pdf'}"
  end

  # Doubles and mocks
  let(:submission_archive_double) { instance_double(SimpleFormsApi::FormRemediation::SubmissionArchive) }
  let(:uploader) { instance_double(SimpleFormsApi::FormRemediation::Uploader) }
  let(:carrier_wave_file) { instance_double(CarrierWave::SanitizedFile, filename: 'mock_file.txt') }
  let(:file_double) { instance_double(File, read: 'content') }
  let(:s3_file) { instance_double(Aws::S3::Object) }

  let(:manifest_entry) do
    [
      submission.created_at,
      form_type,
      benefits_intake_uuid,
      metadata['fileNumber'],
      metadata['veteranFirstName'],
      metadata['veteranLastName']
    ]
  end

  before do
    allow(FileUtils).to receive(:mkdir_p).and_return(true)
    allow(SecureRandom).to receive(:hex).and_return('random-letters-n-numbers')
    allow(File).to receive(:directory?).with(local_archive_path).and_return(false)
    allow(File).to receive(:directory?).with(a_string_including('-manifest')).and_return(false)
    allow(File).to receive(:open).with(local_archive_path).and_yield(file_double)
    allow(File).to receive(:open).with(a_string_including('-manifest')).and_yield(file_double)
    allow(CarrierWave::SanitizedFile).to receive(:new).with(file_double).and_return(carrier_wave_file)
    allow(CSV).to receive(:open).and_return(true)
    allow(SimpleFormsApi::FormRemediation::SubmissionArchive).to(receive(:new).and_return(submission_archive_double))
    allow(submission_archive_double).to receive_messages(
      build!: [local_archive_path, manifest_entry],
      retrieval_data: [local_archive_path, manifest_entry],
      form_number_candidates: [form_type]
    )
    allow(SimpleFormsApi::FormRemediation::Uploader).to receive_messages(new: uploader)
    allow(uploader).to receive_messages(
      get_s3_link: '/s3_url/stuff.pdf',
      s3_exists?: true,
      get_s3_file: s3_file,
      store!: carrier_wave_file
    )
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:error).and_call_original
  end

  %i[submission remediation].each do |archive_type|
    describe "when archiving a #{archive_type}" do
      let(:type) { archive_type }

      describe '.fetch_presigned_url' do
        subject(:fetch_presigned_url) { described_class.fetch_presigned_url(benefits_intake_uuid, config:, type:) }

        it 'returns the s3 link' do
          expect(fetch_presigned_url).to eq('/s3_url/stuff.pdf')
        end

        if archive_type == :remediation
          it 'does not probe legacy S3 paths' do
            fetch_presigned_url
            expect(uploader).not_to have_received(:s3_exists?)
          end
        end
      end

      describe '#initialize' do
        subject(:new) { described_class.new(id: benefits_intake_uuid, type:, config:) }

        context 'when initialized with a valid benefits_intake_uuid' do
          it 'successfully completes initialization' do
            expect { new }.not_to raise_exception
          end
        end
      end

      describe '#upload' do
        shared_examples 's3 client acts as expected' do
          context 'when no errors occur' do
            before { upload }

            it 'logs "uploading" notification' do
              expect(Rails.logger).to have_received(:info).with(
                { message: a_string_including("Uploading #{type}: #{benefits_intake_uuid} to S3 bucket") }
              )
            end

            describe '#log_initialization' do
              it 'logs s3 client initialization notification' do
                expect(Rails.logger).to have_received(:info).with(
                  { message: a_string_including("Initialized S3 Client for #{type} with ID: #{benefits_intake_uuid}") }
                )
              end
            end

            describe '#build_archive!' do
              it 'initializes the submission archive' do
                expect(SimpleFormsApi::FormRemediation::SubmissionArchive).to have_received(:new)
              end

              it 'builds the submission archive' do
                expect(submission_archive_double).to have_received(:build!)
              end
            end

            describe '#upload_to_s3' do
              it 'opens the correct file path(s) and creates/stores sanitized file(s)' do
                expect(File).to have_received(:open).with(local_archive_path).once
                expect(File).to have_received(:open).with(a_string_including('-manifest')).once if type == :remediation

                times = type == :remediation ? 2 : 1
                expect(CarrierWave::SanitizedFile).to have_received(:new).with(file_double).exactly(times).times
                expect(uploader).to have_received(:store!).with(carrier_wave_file).exactly(times).times
              end
            end

            describe '#update_manifest'
            describe '#build_s3_manifest_path'
            describe '#download_manifest'
            describe '#write_and_upload_manifest'

            describe '#s3_uploader' do
              it 'initializes uploader with correct directory' do
                expect(SimpleFormsApi::FormRemediation::Uploader).to have_received(:new).with(
                  config:, directory: s3_archive_dir
                )
              end
            end

            describe '#s3_directory_path'

            describe '#generate_presigned_url' do
              it 'requests the s3 link for the correct file' do
                expect(uploader).to have_received(:get_s3_link).with(s3_archive_path)
              end
            end

            describe '#s3_upload_file_path'
            describe '#presign_required?'
            describe '#manifest_required?'

            describe '#cleanup!' do
              it 'logs clean up notification' do
                expect(Rails.logger).to have_received(:info).with(
                  { message: "Cleaning up path: #{local_archive_path}" }
                )
              end
            end
          end

          context 'when an error occurs' do
            before { allow(File).to receive(:directory?).and_raise('oops') }

            it 'raises the error' do
              expect { upload }.to raise_exception(SimpleFormsApi::FormRemediation::Error, a_string_including('oops'))
            end
          end
        end

        context 'when initialized with a valid id' do
          subject(:upload) { archive_instance.upload }

          let(:archive_instance) { described_class.new(**default_args) }

          include_examples 's3 client acts as expected'
        end

        context 'when initialized with valid submission data' do
          subject(:upload) { archive_instance.upload }

          let(:archive_instance) { described_class.new(**hydrated_submission_args) }

          include_examples 's3 client acts as expected'
        end
      end
    end
  end

  describe '.fetch_presigned_url submission legacy path fallback' do
    subject(:fetch_presigned_url) do
      described_class.fetch_presigned_url(benefits_intake_uuid, config:, type: :submission)
    end

    let(:type) { :submission }
    let(:form_type) { '21P-601' }
    let(:metadata) do
      super().merge('docType' => 'StructuredData:21P-601')
    end
    let(:current_form_number) { 'StructuredData_21P-601' }
    let(:legacy_form_number) { 'StructuredData:21P-601' }
    let(:submission_date) { submission.created_at }
    let(:current_s3_path) do
      dir = "submission/#{dated_directory_name(current_form_number, submission_date)}"
      "#{dir}/#{unique_file_name(current_form_number, benefits_intake_uuid, submission_date)}.pdf"
    end
    let(:legacy_s3_path) do
      dir = "submission/#{dated_directory_name(legacy_form_number, submission_date)}"
      "#{dir}/#{unique_file_name(legacy_form_number, benefits_intake_uuid, submission_date)}.pdf"
    end

    before do
      allow(submission_archive_double).to receive(:form_number_candidates).and_return(
        [current_form_number, legacy_form_number, form_type]
      )
      allow(uploader).to receive(:s3_exists?).with(current_s3_path).and_return(false)
      allow(uploader).to receive(:s3_exists?).with(legacy_s3_path).and_return(true)
      allow(uploader).to receive(:get_s3_link).with(legacy_s3_path).and_return('/s3_url/legacy.pdf')
    end

    it 'returns a presigned url for the legacy path' do
      expect(fetch_presigned_url).to eq('/s3_url/legacy.pdf')
    end

    it 'logs when a legacy path is used' do
      allow(config).to receive(:log_info).and_call_original

      fetch_presigned_url

      expect(config).to have_received(:log_info).with(
        "Found submission PDF at legacy S3 path for #{benefits_intake_uuid}",
        form_number: legacy_form_number,
        s3_path: legacy_s3_path
      )
    end

    context 'when the current path exists' do
      before do
        allow(uploader).to receive(:s3_exists?).with(current_s3_path).and_return(true)
        allow(uploader).to receive(:get_s3_link).with(current_s3_path).and_return('/s3_url/current.pdf')
      end

      it 'returns a presigned url for the current path' do
        expect(fetch_presigned_url).to eq('/s3_url/current.pdf')
      end

      it 'does not log legacy path recovery' do
        allow(config).to receive(:log_info).and_call_original

        fetch_presigned_url

        expect(config).not_to have_received(:log_info).with(
          a_string_including('legacy S3 path'),
          anything
        )
      end
    end

    context 'when probing S3 raises a transient error' do
      let(:error) { Aws::S3::Errors::ServiceError.new(nil, 'timeout') }

      before do
        allow(uploader).to receive(:s3_exists?).with(current_s3_path).and_raise(error)
        allow(config).to receive(:log_error).and_call_original
      end

      it 'falls back to the default presigned url path' do
        expect(fetch_presigned_url).to eq('/s3_url/stuff.pdf')
        expect(uploader).to have_received(:get_s3_link)
      end

      it 'logs the probe error' do
        fetch_presigned_url

        expect(config).to have_received(:log_error).with(
          "Error probing S3 for submission PDF #{benefits_intake_uuid}",
          error,
          form_number: current_form_number,
          s3_path: current_s3_path
        )
      end
    end

    context 'when only the plain form id path exists' do
      let(:plain_s3_path) do
        dir = "submission/#{dated_directory_name(form_type, submission_date)}"
        "#{dir}/#{unique_file_name(form_type, benefits_intake_uuid, submission_date)}.pdf"
      end

      before do
        allow(uploader).to receive(:s3_exists?).with(current_s3_path).and_return(false)
        allow(uploader).to receive(:s3_exists?).with(legacy_s3_path).and_return(false)
        allow(uploader).to receive(:s3_exists?).with(plain_s3_path).and_return(true)
        allow(uploader).to receive(:get_s3_link).with(plain_s3_path).and_return('/s3_url/plain.pdf')
      end

      it 'returns a presigned url for the plain form id path' do
        expect(fetch_presigned_url).to eq('/s3_url/plain.pdf')
      end
    end

    context 'when no candidate paths exist in S3' do
      before do
        allow(uploader).to receive(:s3_exists?).and_return(false)
      end

      it 'falls back to the default presigned url path' do
        expect(fetch_presigned_url).to eq('/s3_url/stuff.pdf')
        expect(uploader).to have_received(:get_s3_link)
      end
    end

    context 'when manifest row is nil' do
      before do
        allow(submission_archive_double).to receive(:retrieval_data).and_return([local_archive_path, nil])
        allow(described_class).to receive(:new).and_wrap_original do |method, **args|
          instance = method.call(**args)
          allow(instance).to receive(:generate_presigned_url).and_return('/s3_url/stuff.pdf')
          instance
        end
      end

      it 'skips legacy path probing and falls back to the default presigned url path' do
        expect(fetch_presigned_url).to eq('/s3_url/stuff.pdf')
        expect(uploader).not_to have_received(:s3_exists?)
      end
    end
  end
end
