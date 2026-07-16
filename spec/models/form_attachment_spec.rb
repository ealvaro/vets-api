# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormAttachment do
  let(:preneed_attachment) { build(:preneed_attachment) }

  describe '#set_file_data!' do
    it 'stores the file and set the file_data' do
      expect(preneed_attachment.parsed_file_data['filename']).to eq('extras.pdf')
    end

    context 'when a virus is detected' do
      let(:uploader_double) { instance_double(PreneedAttachmentUploader) }

      before do
        allow(preneed_attachment).to receive(:get_attachment_uploader).and_return(uploader_double)
        allow(uploader_double).to receive(:store!).and_raise(UploaderVirusScan::VirusFoundError)
      end

      it 'raises UnprocessableEntity with a safe message' do
        file = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'preneeds', 'extras.pdf'))
        expect { preneed_attachment.set_file_data!(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ) do |e|
          expect(e.errors.first.detail).to eq('We were unable to process your file. Please try again.')
        end
      end

      it 'logs a warning' do
        allow(Rails.logger).to receive(:warn)
        file = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'preneeds', 'extras.pdf'))
        expect { preneed_attachment.set_file_data!(file) }.to raise_error(Common::Exceptions::UnprocessableEntity)
        expect(Rails.logger).to have_received(:warn).with(/virus detected/)
      end
    end

    describe '#unlock_pdf' do
      let(:file_name) { 'locked_pdf_password_is_test.Pdf' }
      let(:bad_password) { 'bad_pw' }

      context 'when password is not provided' do
        it 'does not call unlock_pdf' do
          file = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'preneeds', 'extras.pdf'),
                                              'application/pdf')
          expect(preneed_attachment).not_to receive(:unlock_pdf)
          preneed_attachment.set_file_data!(file)
        end
      end

      context 'when file is not a pdf' do
        it 'does not call unlock_pdf' do
          uploader_double = instance_double(PreneedAttachmentUploader)
          allow(preneed_attachment).to receive(:get_attachment_uploader).and_return(uploader_double)
          allow(uploader_double).to receive_messages(
            store!: true,
            filename: 'doctors-note.jpg',
            store_dir: 'preneed_attachments/test-guid'
          )

          file = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.jpg'),
                                              'image/jpeg')
          expect(preneed_attachment).not_to receive(:unlock_pdf)
          preneed_attachment.set_file_data!(file, '123')
        end
      end

      context 'when provided password is incorrect' do
        let(:tempfile) { Tempfile.new(['', "-#{file_name}"]) }
        let(:file) do
          ActionDispatch::Http::UploadedFile.new(original_filename: file_name, type: 'application/pdf', tempfile:)
        end

        before do
          allow(Rails.logger).to receive(:warn)
        end

        it 'logs a sanitized message to Rails logger' do
          error_message = nil
          allow(Rails.logger).to receive(:warn) do |message|
            error_message = message
          end

          expect do
            preneed_attachment.set_file_data!(file, bad_password)
          end.to raise_error(Common::Exceptions::UnprocessableEntity)
          expect(error_message).not_to include(file_name)
          expect(error_message).not_to include(bad_password)
        end

        it 'raises an exception without a cause to prevent leaking sensitive data' do
          raised_error = nil
          begin
            preneed_attachment.set_file_data!(file, bad_password)
          rescue Common::Exceptions::UnprocessableEntity => e
            raised_error = e
          end

          expect(raised_error).to be_present
          expect(raised_error.cause).to be_nil
        end

        it 'does not expose lower-level PDF processing errors in the exception chain' do
          raised_error = nil
          begin
            preneed_attachment.set_file_data!(file, bad_password)
          rescue Common::Exceptions::UnprocessableEntity => e
            raised_error = e
          end

          # Walk the entire cause chain to ensure no sensitive data leaks
          current = raised_error
          while current
            expect(current.message).not_to include(bad_password)
            current = current.cause
          end
        end
      end
    end
  end

  describe '#get_file' do
    it 'gets the file from storage' do
      preneed_attachment.save!
      preneed_attachment2 = Preneeds::PreneedAttachment.find(preneed_attachment.id)
      file = preneed_attachment2.get_file

      expect(file.exists?).to be(true)
    end
  end

  describe 'S3 read logging' do
    it 'logs successful S3 read' do
      form_attachment = FormAttachment.new(guid: 'test-guid-123')
      form_attachment.file_data = { filename: 'test.pdf' }.to_json

      uploader_double = instance_double(HCAAttachmentUploader)
      allow(form_attachment).to receive(:get_attachment_uploader).and_return(uploader_double)
      allow(uploader_double).to receive_messages(
        store_dir: 'hca_attachments',
        retrieve_from_store!: true,
        file: 'file_obj'
      )

      allow(Rails.logger).to receive(:info)

      form_attachment.get_file

      expect(Rails.logger).to have_received(:info).with(
        %r{\[HCA_S3_READ\].*correlation_id=#{form_attachment.guid}.*s3_key=hca_attachments/\[REDACTED\]}
      )
    end

    it 'logs S3 read failure with safe error metadata only' do
      form_attachment = FormAttachment.new(guid: 'test-guid-456')
      form_attachment.file_data = { filename: 'missing.pdf' }.to_json

      uploader_double = instance_double(HCAAttachmentUploader)
      allow(form_attachment).to receive(:get_attachment_uploader).and_return(uploader_double)
      allow(uploader_double).to receive(:store_dir).and_return('hca_attachments')
      allow(uploader_double).to receive(:retrieve_from_store!).and_raise(Errno::ENOENT, 'File not found')

      allow(Rails.logger).to receive(:error)

      expect { form_attachment.get_file }.to raise_error(Errno::ENOENT)

      expected_pattern = Regexp.new(
        "\\[HCA_S3_READ_FAILURE\\].*correlation_id=#{form_attachment.guid}" \
        '.*s3_key=hca_attachments/\\[REDACTED\\].*error_code=Errno::ENOENT' \
        '.*exception_class=Errno::ENOENT'
      )

      expect(Rails.logger).to have_received(:error)
        .with(
          expected_pattern
        )
    end
  end

  describe 'S3 write logging' do
    it 'logs successful S3 write' do
      form_attachment = FormAttachment.new(guid: 'write-guid-123')

      uploader_double = instance_double(HCAAttachmentUploader)
      allow(form_attachment).to receive(:get_attachment_uploader).and_return(uploader_double)
      allow(uploader_double).to receive_messages(
        store_dir: 'hca_attachments',
        filename: 'doc.pdf',
        store!: true
      )

      file = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'preneeds', 'extras.pdf'))

      allow(Rails.logger).to receive(:info)

      form_attachment.set_file_data!(file)

      expect(Rails.logger).to have_received(:info).with(
        /\[HCA_S3_WRITE\].*correlation_id=#{form_attachment.guid}/
      )
    end

    it 'logs S3 write failure on virus detected' do
      form_attachment = FormAttachment.new(guid: 'virus-guid')

      uploader_double = instance_double(HCAAttachmentUploader)
      allow(form_attachment).to receive(:get_attachment_uploader).and_return(uploader_double)
      allow(uploader_double).to receive(:store!).and_raise(UploaderVirusScan::VirusFoundError)

      file = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'preneeds', 'extras.pdf'))

      allow(Rails.logger).to receive(:warn)

      expect { form_attachment.set_file_data!(file) }.to raise_error(Common::Exceptions::UnprocessableEntity)

      expect(Rails.logger).to have_received(:warn).with(/virus detected/)
    end

    it 'logs S3 write failure on integrity error' do
      form_attachment = FormAttachment.new(guid: 'integrity-guid')

      uploader_double = instance_double(HCAAttachmentUploader)
      allow(form_attachment).to receive(:get_attachment_uploader).and_return(uploader_double)
      allow(uploader_double).to receive(:store!).and_raise(CarrierWave::IntegrityError, 'File size too large')

      file = Rack::Test::UploadedFile.new(Rails.root.join('spec', 'fixtures', 'preneeds', 'extras.pdf'))

      allow(Rails.logger).to receive(:warn)

      expect { form_attachment.set_file_data!(file) }.to raise_error(Common::Exceptions::UnprocessableEntity)

      expect(Rails.logger).to have_received(:warn).with(/File size too large/)
    end
  end
end
