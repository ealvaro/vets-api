# frozen_string_literal: true

require 'rails_helper'
require 'hexapdf'

RSpec.describe FormAttachment do
  let(:test_form_attachment_class) do
    uploader_class = Class.new(CarrierWave::Uploader::Base) do
      def store_dir
        'test_uploads'
      end
    end

    Class.new(FormAttachment) do
      self.table_name = 'form_attachments'
      const_set(:ATTACHMENT_UPLOADER_CLASS, uploader_class)
    end
  end

  let(:form_attachment) { test_form_attachment_class.new(guid: SecureRandom.uuid) }

  describe '#unlock_pdf' do
    let(:file_name) { 'locked_pdf_password_is_test.pdf' }
    let(:user_password) { 'super_secret_password_123' }

    context 'when provided password is incorrect' do
      let(:file) do
        fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', file_name), 'application/pdf')
      end

      before do
        allow(Rails.logger).to receive(:warn)
      end

      it 'raises UnprocessableEntity' do
        expect do
          form_attachment.set_file_data!(file, user_password)
        end.to raise_error(Common::Exceptions::UnprocessableEntity)
      end

      it 'logs a fixed safe error message to Rails logger' do
        logged_message = nil
        allow(Rails.logger).to receive(:warn) do |message|
          logged_message = message
        end

        expect do
          form_attachment.set_file_data!(file, user_password)
        end.to raise_error(Common::Exceptions::UnprocessableEntity)

        expect(logged_message).to be_present
        expect(logged_message).to eq('FormAttachment.unlock_pdf error: incorrect password provided')
      end

      it 'returns the exact incorrect password message' do
        raised_error = nil
        begin
          form_attachment.set_file_data!(file, user_password)
        rescue Common::Exceptions::UnprocessableEntity => e
          raised_error = e
        end

        expect(raised_error).to be_a(Common::Exceptions::UnprocessableEntity)
        expect(raised_error.errors.first.detail).to eq('The password you entered is incorrect. Please try again.')
      end

      it 'raises an exception without a cause to prevent leaking sensitive data' do
        raised_error = nil
        begin
          form_attachment.set_file_data!(file, user_password)
        rescue Common::Exceptions::UnprocessableEntity => e
          raised_error = e
        end

        # The cause should be nil so upstream error-reporting does not include
        # sensitive details from lower-level PDF processing exceptions.
        expect(raised_error).to be_present
        expect(raised_error.cause).to be_nil
      end

      it 'does not expose the password anywhere in the exception chain' do
        raised_error = nil
        begin
          form_attachment.set_file_data!(file, user_password)
        rescue Common::Exceptions::UnprocessableEntity => e
          raised_error = e
        end

        # Walk the entire cause chain to ensure no sensitive data leaks
        current = raised_error
        while current
          expect(current.message).not_to include(user_password)
          expect(current.message).not_to include(file_name)
          current = current.cause
        end
      end

      it 'does not expose the filename anywhere in the exception chain' do
        raised_error = nil
        begin
          form_attachment.set_file_data!(file, user_password)
        rescue Common::Exceptions::UnprocessableEntity => e
          raised_error = e
        end

        current = raised_error
        while current
          expect(current.message).not_to include(file_name)
          current = current.cause
        end
      end
    end

    context 'when provided password is correct' do
      let(:user_password) { 'test' }
      let(:file) do
        fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', file_name), 'application/pdf')
      end
      let(:adobe_password) { '123456' }
      let(:adobe_file) do
        fixture_file_upload(
          Rails.root.join('spec', 'fixtures', 'hca', 'adobe_encrypted_file_with_password_123456.pdf'),
          'application/pdf'
        )
      end

      it 'stores an unlocked pdf in attachment storage' do
        form_attachment.set_file_data!(file, user_password)
        stored_file = form_attachment.get_file

        expect { HexaPDF::Document.open(stored_file.path) }.not_to raise_error
      end

      it 'stores an unlocked adobe-encrypted pdf in attachment storage' do
        form_attachment.set_file_data!(adobe_file, adobe_password)
        stored_file = form_attachment.get_file

        expect { HexaPDF::Document.open(stored_file.path) }.not_to raise_error
      end
    end

    context 'when PDF is invalid or malformed' do
      let(:file) do
        fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'malformed-pdf.pdf'), 'application/pdf')
      end

      # Be sure to check a single space character as a bad password, it's a special case that has caused a bug before
      ['test', ' '].each do |password|
        it "returns invalid-pdf detail and does not map to incorrect password (password: '#{password}')" do
          raised_error = nil
          begin
            form_attachment.set_file_data!(file, password)
          rescue Common::Exceptions::UnprocessableEntity => e
            raised_error = e
          end

          expect(raised_error).to be_a(Common::Exceptions::UnprocessableEntity)
          expect(raised_error.errors.first.detail).to eq(I18n.t('errors.messages.uploads.pdf.invalid'))
          expect(raised_error.errors.first.detail).not_to eq('The password you entered is incorrect. Please try again.')
        end
      end
    end
  end
end
