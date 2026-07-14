# frozen_string_literal: true

require 'rails_helper'

require 'common/pdf_helpers'

describe Common::PdfHelpers do
  describe '#unlock_pdf' do
    let(:file_name) { 'aes256_password.pdf' }
    let(:bad_password) { 'bad_pw_test' }
    let(:password) { 'test' }

    context 'when provided password is incorrect' do
      it 'logs a message' do
        error_message = nil
        allow(Rails.logger).to receive(:warn) do |message|
          error_message = message
        end

        input_file = Rack::Test::UploadedFile.new('spec/fixtures/files/aes256_password.pdf', 'application/pdf')
        output_file = Tempfile.new(['encrypted_attachment', '.pdf'])

        expect { subject.unlock_pdf(input_file, bad_password, output_file) }
          .to raise_error(Common::Exceptions::UnprocessableEntity)

        expect(error_message).to eq 'Invalid password specified'
      end
    end

    context 'when provided password is correct' do
      it 'does not log a message' do
        input_file = Rack::Test::UploadedFile.new('spec/fixtures/files/aes256_password.pdf', 'application/pdf')
        output_file = Tempfile.new(['encrypted_attachment', '.pdf'])

        expect(Rails.logger).not_to receive(:warn)
        expect { subject.unlock_pdf(input_file, password, output_file) }
          .not_to raise_error
      end
    end
  end
end
