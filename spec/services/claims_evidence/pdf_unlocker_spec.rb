# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsEvidence::PdfUnlocker do
  def with_staged(fixture, name: fixture, password: nil)
    src = Rails.root.join('spec', 'fixtures', 'files', fixture)
    Tempfile.create(['staged', File.extname(fixture)]) do |tmp|
      tmp.binmode
      IO.copy_stream(src, tmp)
      tmp.flush
      yield described_class.new(tmp, name, password:), tmp
    end
  end

  # No fixture for this one: only permissions are restricted, so the document opens with any
  # password or none at all.
  def with_owner_locked(password:)
    Tempfile.create(['owner-only', '.pdf']) do |tmp|
      # PdfUnlocker writes the decrypted bytes back through this handle.
      tmp.binmode
      doc = HexaPDF::Document.open(Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf'))
      doc.encrypt(owner_password: 'secret-owner', permissions: [:print])
      doc.write(tmp.path, validate: false)
      yield described_class.new(tmp, 'owner_only.pdf', password:), tmp
    end
  end

  def encrypted?(path)
    HexaPDF::Document.open(path).encrypted?
  rescue HexaPDF::EncryptionError
    # Locked with a user password, so it can't be opened to be asked.
    true
  end

  def expect_rejection(unlocker, reason:, code:)
    expect { unlocker.unlock! }.to raise_error(described_class::Rejected) { |error|
      expect(error.reason).to eq(reason)
      expect(error.code).to eq(code)
    }
  end

  describe '#unlock!' do
    context 'with a PDF locked by a user password' do
      let(:fixture) { 'locked_pdf_password_is_test.pdf' }

      it 'decrypts the file in place when given the correct password' do
        with_staged(fixture, password: 'test') do |unlocker, tmp|
          expect { unlocker.unlock! }.to change { encrypted?(tmp.path) }.from(true).to(false)
        end
      end

      it 'leaves the decrypted PDF readable' do
        with_staged(fixture, password: 'test') do |unlocker, tmp|
          unlocker.unlock!
          expect(HexaPDF::Document.open(tmp.path).pages.count).to eq(1)
        end
      end

      it 'rejects an incorrect password' do
        with_staged(fixture, password: 'not-the-password') do |unlocker, _tmp|
          expect_rejection(unlocker, reason: 'incorrect_password', code: 'DOC_UPLOAD_INCORRECT_PASSWORD')
        end
      end

      it 'rejects a missing password' do
        with_staged(fixture) do |unlocker, _tmp|
          expect_rejection(unlocker, reason: 'encrypted_pdf', code: 'DOC_UPLOAD_ENCRYPTED_PDF')
        end
      end

      it 'leaves the file untouched when it rejects' do
        with_staged(fixture, password: 'not-the-password') do |unlocker, tmp|
          expect { unlocker.unlock! }.to raise_error(described_class::Rejected)
          expect(encrypted?(tmp.path)).to be(true)
        end
      end

      # The password is in scope when PdfHelpers raises, so the rejection must not carry
      # that exception forward as its cause.
      it 'does not chain the underlying exception' do
        with_staged(fixture, password: 'not-the-password') do |unlocker, _tmp|
          expect { unlocker.unlock! }.to raise_error(described_class::Rejected) { |error|
            expect(error.cause).to be_nil
          }
        end
      end
    end

    context 'with a PDF carrying only an owner password' do
      [nil, '', 'whatever-the-veteran-typed', 'secret-owner'].each do |password|
        it "strips the encryption when given #{password.inspect}" do
          with_owner_locked(password:) do |unlocker, tmp|
            expect { unlocker.unlock! }.to change { encrypted?(tmp.path) }.from(true).to(false)
          end
        end
      end
    end

    context 'with a file it should not touch' do
      it 'passes a non-PDF through untouched' do
        with_staged('va.gif') do |unlocker, tmp|
          expect { unlocker.unlock! }.not_to(change { Digest::SHA256.file(tmp.path).hexdigest })
        end
      end

      it 'leaves an unencrypted PDF alone' do
        with_staged('doctors-note.pdf') do |unlocker, tmp|
          expect { unlocker.unlock! }.not_to(change { Digest::SHA256.file(tmp.path).hexdigest })
        end
      end

      # An encrypted PDF renamed to .txt is not detected, matching LighthouseDocument.
      it 'skips a PDF whose name does not end in .pdf' do
        with_staged('locked_pdf_password_is_test.pdf', name: 'evidence.txt') do |unlocker, _tmp|
          expect { unlocker.unlock! }.not_to raise_error
        end
      end
    end

    context 'when an encrypted PDF cannot be rewritten' do
      before do
        allow(Common::PdfHelpers).to receive(:unlock_pdf).and_raise(
          Common::Exceptions::UnprocessableEntity.new(
            detail: I18n.t('errors.messages.uploads.pdf.invalid'),
            source: 'Common::PdfHelpers.unlock_pdf'
          )
        )
      end

      it 'rejects it as invalid rather than as a password failure' do
        with_staged('locked_pdf_password_is_test.pdf', password: 'test') do |unlocker, _tmp|
          expect_rejection(unlocker, reason: 'invalid_pdf', code: 'DOC_UPLOAD_INVALID_PDF')
        end
      end
    end

    context 'with a file that is not readable as a PDF' do
      it 'rejects it as invalid' do
        Tempfile.create(['broken', '.pdf']) do |tmp|
          tmp.binmode
          tmp.write('%PDF-1.4 this is not a real pdf')
          tmp.flush

          expect_rejection(described_class.new(tmp, 'broken.pdf'),
                           reason: 'invalid_pdf', code: 'DOC_UPLOAD_INVALID_PDF')
        end
      end
    end
  end
end
