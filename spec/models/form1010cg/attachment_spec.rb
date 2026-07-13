# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form1010cg::Attachment, type: :model do
  let(:guid) { 'cdbaedd7-e268-49ed-b714-ec543fbb1fb8' }
  let(:subject) { described_class.new(guid:) }
  let(:vcr_options) do
    {
      record: :none,
      allow_unused_http_interactions: false,
      match_requests_on: %i[method host body]
    }
  end

  it 'is a FormAttachment model' do
    expect(described_class.ancestors).to include(FormAttachment)
  end

  it 'has an uploader configured' do
    expect(described_class::ATTACHMENT_UPLOADER_CLASS).to eq(Form1010cg::PoaUploader)
  end

  describe '#to_local_file', skip: 'VCR failures' do
    let(:file_fixture_path) { Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.jpg') }
    let(:expected_local_file_path) { "tmp/#{guid}_doctors-note.jpg" }
    let(:remote_file_content) { nil }

    before do
      VCR.use_cassette("s3/object/put/#{guid}/doctors-note_jpg", vcr_options) do
        subject.set_file_data!(
          Rack::Test::UploadedFile.new(file_fixture_path, 'image/jpg')
        )
      end
    end

    after do
      FileUtils.rm_f(expected_local_file_path)
    end

    it 'makes a local copy of the file' do
      VCR.use_cassette("s3/object/get/#{guid}/doctors-note_jpg", vcr_options) do
        expect(subject.to_local_file).to eq(expected_local_file_path)
        expect(
          FileUtils.compare_file(expected_local_file_path, file_fixture_path)
        ).to be(true)
      end
    end
  end

  describe '#set_file_data!' do
    let(:uploaded_file) do
      tempfile = Tempfile.new(['locked_pdf_password_is_test', '.pdf'])
      tempfile.binmode
      tempfile.write(File.binread('spec/fixtures/files/locked_pdf_password_is_test.pdf'))
      tempfile.rewind

      ActionDispatch::Http::UploadedFile.new(
        tempfile:,
        filename: 'locked_pdf_password_is_test.pdf',
        type: 'application/pdf'
      )
    end
    let(:attachment_uploader) do
      instance_double(
        Form1010cg::PoaUploader,
        filename: 'locked_pdf_password_is_test.pdf',
        store_dir: guid
      )
    end

    before do
      allow(Form1010cg::PoaUploader).to receive(:new).and_return(attachment_uploader)
      allow(attachment_uploader).to receive(:store!)
    end

    after do
      uploaded_file.tempfile.close!
    rescue Errno::ENOENT, IOError
      nil
    end

    it 'uses HexaPDF helper to unlock encrypted PDFs with a provided password' do
      expect(Common::PdfHelpers).to receive(:unlock_pdf).once.and_call_original

      subject.set_file_data!(uploaded_file, 'test')

      expect(attachment_uploader).to have_received(:store!).once
      expect(subject.parsed_file_data['filename']).to eq('locked_pdf_password_is_test.pdf')
    end

    it 'does not attempt to decrypt when password is not provided' do
      expect(Common::PdfHelpers).not_to receive(:unlock_pdf)

      subject.set_file_data!(uploaded_file)

      expect(attachment_uploader).to have_received(:store!).once
    end

    it 'logs a hard-coded message and raises normalized unlock error data' do
      unsanitized_error = Common::Exceptions::UnprocessableEntity.new(
        detail: '/tmp/sensitive-user-filename.pdf bad password',
        source: 'UnexpectedSource'
      )

      allow(Common::PdfHelpers).to receive(:unlock_pdf).and_raise(unsanitized_error)
      expect(Rails.logger).to receive(:warn).with('[Form 10-10CG] PDF unlock failed: invalid pdf provided')

      expect { subject.set_file_data!(uploaded_file, 'test') }
        .to raise_error(Common::Exceptions::UnprocessableEntity) do |error|
          expect(error.errors.first.source).to eq('Common::PdfHelpers.unlock_pdf')
          expect(error.errors.first.detail).to eq(I18n.t('errors.messages.uploads.pdf.invalid'))
        end
    end
  end
end
