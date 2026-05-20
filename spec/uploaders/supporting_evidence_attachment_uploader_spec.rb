# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SupportingEvidenceAttachmentUploader, :uploader_helpers do
  subject { described_class.new(guid) }

  let(:guid) { '1234' }

  it 'allows image, pdf, and text files' do
    expect(subject.extension_allowlist).to match_array %w[pdf png gif tiff tif jpeg jpg bmp txt]
  end

  describe '#size_range' do
    it 'allows files up to 100MB to match the Benefits Intake API limit' do
      expect(subject.size_range).to eq((1.byte)..(100.megabytes))
    end
  end

  it 'returns a store directory containing guid' do
    expect(subject.store_dir).to eq "disability_compensation_supporting_form/#{guid}"
  end

  it 'throws an error if no guid is given' do
    blank_uploader = described_class.new(nil)
    expect { blank_uploader.store_dir }.to raise_error(RuntimeError, 'missing guid')
  end

  describe '#filename' do
    context 'when no file has been stored' do
      it 'returns nil' do
        expect(subject.filename).to be_nil
      end
    end

    context 'when filename is within MAX_FILENAME_LENGTH' do
      let(:short_filename) { 'short_file.pdf' }

      before do
        # CarrierWave's filename method uses @filename internally after sanitization
        subject.instance_variable_set(:@filename, short_filename)
      end

      it 'returns the filename unchanged' do
        expect(subject.filename).to eq(short_filename)
      end
    end

    context 'when filename exceeds MAX_FILENAME_LENGTH' do
      let(:long_filename) { "#{'a' * 150}.pdf" }

      before do
        subject.instance_variable_set(:@filename, long_filename)
      end

      it 'returns a shortened filename' do
        result = subject.filename
        expect(result.length).to be <= described_class::MAX_FILENAME_LENGTH
      end

      it 'preserves the file extension' do
        result = subject.filename
        expect(result).to end_with('.pdf')
      end
    end

    context 'when filename has a long extension' do
      let(:long_ext_filename) { "#{'a' * 150}.jpeg" }

      before do
        subject.instance_variable_set(:@filename, long_ext_filename)
      end

      it 'accounts for extension length in the shortened result' do
        result = subject.filename
        expect(result.length).to be <= described_class::MAX_FILENAME_LENGTH
        expect(result).to end_with('.jpeg')
      end
    end
  end

  describe '#shorten_filename' do
    context 'when filename is within MAX_FILENAME_LENGTH' do
      it 'returns the filename unchanged' do
        expect(subject.send(:shorten_filename, 'short.pdf')).to eq('short.pdf')
      end
    end

    context 'when filename is exactly MAX_FILENAME_LENGTH' do
      let(:exact_filename) { "#{'a' * 96}.pdf" } # 96 + 4 (.pdf) = 100

      it 'returns the filename unchanged' do
        expect(subject.send(:shorten_filename, exact_filename)).to eq(exact_filename)
      end
    end

    context 'when filename exceeds MAX_FILENAME_LENGTH' do
      let(:long_filename) { "#{'a' * 150}.pdf" }

      it 'returns a shortened filename within limit' do
        result = subject.send(:shorten_filename, long_filename)
        expect(result.length).to be <= described_class::MAX_FILENAME_LENGTH
      end

      it 'preserves the file extension' do
        result = subject.send(:shorten_filename, long_filename)
        expect(result).to end_with('.pdf')
      end
    end

    context 'when filename has no extension' do
      let(:long_filename_no_ext) { 'a' * 150 }

      it 'shortens to MAX_FILENAME_LENGTH' do
        result = subject.send(:shorten_filename, long_filename_no_ext)
        expect(result.length).to eq(described_class::MAX_FILENAME_LENGTH)
      end
    end

    context 'when filename has multiple dots' do
      let(:multi_dot_filename) { "#{'a' * 150}.document.v2.pdf" }

      it 'preserves only the last extension' do
        result = subject.send(:shorten_filename, multi_dot_filename)
        expect(result).to end_with('.pdf')
        expect(result.length).to be <= described_class::MAX_FILENAME_LENGTH
      end
    end
  end

  describe 'logging methods' do
    let(:mock_file) do
      double('uploaded_file', size: 1024, headers: {
               'Content-Type' => 'application/pdf',
               'User-Agent' => 'Mozilla/5.0',
               'filename' => 'PII.pdf'
             })
    end

    describe '#log_transaction_start' do
      it 'logs process_id, filesize, and upload_start without file_headers' do
        freeze_time = Time.parse('2025-08-26 12:00:00 UTC')

        allow(Time).to receive(:current).and_return(freeze_time)
        allow(Rails.logger).to receive(:info)

        subject.log_transaction_start(mock_file)

        expected_log = {
          process_id: Process.pid,
          filesize: 1024,
          upload_start: freeze_time
        }

        expect(Rails.logger).to have_received(:info).with(expected_log)
      end

      it 'does not log file headers which could contain PII' do
        allow(Rails.logger).to receive(:info) do |log_data|
          expect(log_data).not_to have_key(:file_headers)
          expect(log_data.values.join).not_to include('Mozilla')
          expect(log_data.values.join).not_to include('User-Agent')
          expect(log_data.values.join).not_to include('PII.pdf')
        end

        subject.log_transaction_start(mock_file)

        expect(Rails.logger).to have_received(:info)
      end
    end

    describe '#log_transaction_complete' do
      it 'logs process_id, filesize, and upload_complete without file_headers' do
        freeze_time = Time.parse('2025-08-26 12:00:00 UTC')

        allow(Time).to receive(:current).and_return(freeze_time)
        allow(Rails.logger).to receive(:info)

        subject.log_transaction_complete(mock_file)

        expected_log = {
          process_id: Process.pid,
          filesize: 1024,
          upload_complete: freeze_time
        }

        expect(Rails.logger).to have_received(:info).with(expected_log)
      end

      it 'does not log file headers which could contain PII' do
        allow(Rails.logger).to receive(:info) do |log_data|
          expect(log_data).not_to have_key(:file_headers)
          expect(log_data.values.join).not_to include('Mozilla')
          expect(log_data.values.join).not_to include('User-Agent')
        end

        subject.log_transaction_complete(mock_file)

        expect(Rails.logger).to have_received(:info)
      end
    end
  end

  describe '#validate_with_benefits_intake_constraints' do
    let(:mock_file) { double('file', path: file_path) }

    context 'with a non-PDF file' do
      let(:file_path) { 'spec/fixtures/files/va.gif' }

      it 'skips validation entirely' do
        expect(PDFUtilities::PDFValidator::Validator).not_to receive(:new)
        subject.send(:validate_with_benefits_intake_constraints, mock_file)
      end
    end

    context 'with a valid PDF' do
      let(:file_path) { 'spec/fixtures/files/doctors-note.pdf' }

      it 'does not raise an error' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.not_to raise_error
      end
    end

    context 'with a PDF that has oversized pages (width exceeds 78in)' do
      let(:file_path) { 'spec/fixtures/pdf_utilities/pdf_validator/79x10.pdf' }

      it 'raises a CarrierWave::IntegrityError with page size message' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError, /page size limit/i
        )
      end

      it 'increments the StatsD rejection metric with reason tag' do
        expect(StatsD).to receive(:increment).with(
          'api.disability_compensation.upload_validation.rejected',
          tags: ['reason:benefits_intake_pdf_invalid']
        )
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError
        )
      end

      it 'logs the rejection with structured details' do
        allow(Rails.logger).to receive(:warn)
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError
        )
        expect(Rails.logger).to have_received(:warn).with(
          hash_including(
            message: 'Form 526 upload validation rejected',
            reason: 'benefits_intake_pdf_invalid',
            file_extension: '.pdf',
            guid: '1234'
          )
        )
      end
    end

    context 'with a PDF that has oversized pages (height exceeds 101in)' do
      let(:file_path) { 'spec/fixtures/pdf_utilities/pdf_validator/10x102.pdf' }

      it 'raises a CarrierWave::IntegrityError with page size message' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError, /page size limit/i
        )
      end

      it 'increments the StatsD rejection metric' do
        expect(StatsD).to receive(:increment).with(
          'api.disability_compensation.upload_validation.rejected',
          tags: ['reason:benefits_intake_pdf_invalid']
        )
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError
        )
      end
    end

    context 'with a PDF within page limits (21x21)' do
      let(:file_path) { 'spec/fixtures/pdf_utilities/pdf_validator/21x21.pdf' }

      it 'does not raise an error' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.not_to raise_error
      end
    end

    context 'with an owner-password encrypted PDF' do
      let(:file_path) { 'spec/fixtures/pdf_utilities/pdf_validator/encrypted.pdf' }

      it 'does not raise an error (encryption checking is deferred to ValidatePdf)' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.not_to raise_error
      end
    end

    context 'with a user-password locked PDF' do
      let(:file_path) { 'spec/fixtures/pdf_utilities/pdf_validator/locked.pdf' }

      # User-password PDFs cause a PdfInfo::MetadataReadError during metadata read, which
      # PDFValidator always catches (not gated by check_encryption). In practice, ValidatePdf
      # fires first in the callback chain and rejects these before our code runs.
      it 'still catches it (metadata read failure is not gated by check_encryption)' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError, /locked with a user password/i
        )
      end

      it 'increments the StatsD rejection metric' do
        expect(StatsD).to receive(:increment).with(
          'api.disability_compensation.upload_validation.rejected',
          tags: ['reason:benefits_intake_pdf_invalid']
        )
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError
        )
      end
    end

    context 'with a PDF exceeding the 100MB size limit' do
      let(:file_path) { 'spec/fixtures/files/doctors-note.pdf' }

      before do
        allow(File).to receive(:size).with(file_path).and_return(101.megabytes)
      end

      it 'raises a CarrierWave::IntegrityError with file size message' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError, /file size limit/i
        )
      end

      it 'increments the StatsD rejection metric' do
        expect(StatsD).to receive(:increment).with(
          'api.disability_compensation.upload_validation.rejected',
          tags: ['reason:benefits_intake_pdf_invalid']
        )
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError
        )
      end
    end

    context 'with an invalid (non-PDF) file disguised with .pdf extension' do
      let(:file_path) { 'spec/fixtures/pdf_utilities/pdf_validator/metadata.json' }

      before do
        # Pretend the file has a .pdf extension
        allow(File).to receive(:extname).with(file_path).and_return('.pdf')
        allow(mock_file).to receive(:path).and_return(file_path)
      end

      it 'raises a CarrierWave::IntegrityError with invalid PDF message' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError, /not a valid PDF/i
        )
      end

      it 'increments the StatsD rejection metric' do
        expect(StatsD).to receive(:increment).with(
          'api.disability_compensation.upload_validation.rejected',
          tags: ['reason:benefits_intake_pdf_invalid']
        )
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError
        )
      end
    end

    context 'when PDFValidator returns multiple errors' do
      let(:file_path) { 'spec/fixtures/files/doctors-note.pdf' }
      let(:mock_result) { double('result', valid_pdf?: false, errors: ['Error one', 'Error two']) }
      let(:mock_validator) { double('validator', validate: mock_result) }

      before do
        allow(PDFUtilities::PDFValidator::Validator).to receive(:new).and_return(mock_validator)
      end

      it 'joins all errors in the exception message' do
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError, 'Error one. Error two'
        )
      end

      it 'includes the joined errors in the log' do
        allow(Rails.logger).to receive(:warn)
        expect { subject.send(:validate_with_benefits_intake_constraints, mock_file) }.to raise_error(
          CarrierWave::IntegrityError
        )
        expect(Rails.logger).to have_received(:warn).with(
          hash_including(error_detail: 'Error one. Error two')
        )
      end
    end

    it 'uses BENEFITS_INTAKE_VALIDATOR_OPTIONS (check_encryption disabled)' do
      file_path = 'spec/fixtures/files/doctors-note.pdf'
      mock_file = double('file', path: file_path)

      expect(PDFUtilities::PDFValidator::Validator).to receive(:new).with(
        file_path, described_class::BENEFITS_INTAKE_VALIDATOR_OPTIONS
      ).and_call_original

      subject.send(:validate_with_benefits_intake_constraints, mock_file)
    end

    it 'has check_encryption disabled' do
      expect(described_class::BENEFITS_INTAKE_VALIDATOR_OPTIONS[:check_encryption]).to be(false)
    end

    it 'inherits all other options from BenefitsIntake::Service::PDF_VALIDATOR_OPTIONS' do
      intake_opts = BenefitsIntake::Service::PDF_VALIDATOR_OPTIONS
      validator_opts = described_class::BENEFITS_INTAKE_VALIDATOR_OPTIONS

      intake_opts.each_key do |key|
        next if key == :check_encryption

        expect(validator_opts[key]).to eq(intake_opts[key]),
                                       "Expected #{key} to be #{intake_opts[key]} but got #{validator_opts[key]}"
      end
    end
  end

  describe '#validate_virus_free' do
    stub_virus_scan

    # Stubbing Rails.env.production? causes SupportingEvidenceAttachmentUploader#initialize
    # to call set_aws_config, which permanently mutates self.class.storage = :aws.
    # Without this around block, that class-level mutation leaks into subsequent tests,
    # causing "No region was provided" errors when CarrierWave tries to connect to S3.
    around do |example|
      previous_storage = described_class._storage
      example.run
    ensure
      described_class.storage previous_storage
    end

    before do
      allow(Rails.env).to receive(:production?).and_return(true)
    end

    context 'when no virus is detected' do
      it 'does not raise an error' do
        file = Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif')

        expect { subject.send(:validate_virus_free, file) }.not_to raise_error
      end
    end

    context 'when a virus is detected' do
      before do
        allow(Common::VirusScan).to receive(:scan).and_return(false)
      end

      it 'raises a CarrierWave::IntegrityError instead of VirusFoundError' do
        file = Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif')
        allow(file).to receive(:delete)

        expect { subject.send(:validate_virus_free, file) }.to raise_error(
          CarrierWave::IntegrityError,
          'We were unable to process your file. Please try again.'
        )
      end

      it 'does not raise VirusFoundError' do
        file = Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif')
        allow(file).to receive(:delete)

        expect { subject.send(:validate_virus_free, file) }.to raise_error(CarrierWave::IntegrityError)
      end

      it 'does not mention virus in the error message' do
        file = Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif')
        allow(file).to receive(:delete)

        expect { subject.send(:validate_virus_free, file) }.to raise_error(CarrierWave::IntegrityError) do |error|
          expect(error.message).not_to match(/virus/i)
          expect(error.message).not_to match(/malware/i)
        end
      end

      it 'increments the StatsD rejection metric with virus_detected reason' do
        file = Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif')
        allow(file).to receive(:delete)

        expect(StatsD).to receive(:increment).with(
          'api.disability_compensation.upload_validation.rejected',
          tags: ['reason:virus_detected']
        )
        expect { subject.send(:validate_virus_free, file) }.to raise_error(CarrierWave::IntegrityError)
      end

      it 'logs the virus rejection with structured details' do
        file = Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif')
        allow(file).to receive(:delete)
        allow(Rails.logger).to receive(:warn)

        expect { subject.send(:validate_virus_free, file) }.to raise_error(CarrierWave::IntegrityError)
        expect(Rails.logger).to have_received(:warn).with(
          hash_including(
            message: 'Form 526 upload validation rejected',
            reason: 'virus_detected',
            guid: '1234'
          )
        )
      end
    end

    context 'when not in production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'skips the virus scan' do
        file = Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif')

        expect(Common::VirusScan).not_to receive(:scan)
        expect { subject.send(:validate_virus_free, file) }.not_to raise_error
      end
    end
  end

  describe 'store! integration' do
    stub_virus_scan

    around do |example|
      previous_storage = described_class._storage
      described_class.storage :file
      example.run
    ensure
      described_class.storage previous_storage
    end

    before do
      # Stub the ValidatePdf callback (depends on pdfinfo binary)
      allow_any_instance_of(described_class).to receive(:validate_pdf)
    end

    it 'rejects oversized PDFs during store' do
      file = Rack::Test::UploadedFile.new(
        'spec/fixtures/pdf_utilities/pdf_validator/79x10.pdf', 'application/pdf'
      )

      expect { subject.store!(file) }.to raise_error(CarrierWave::IntegrityError, /page size limit/i)
    end
  end
end
