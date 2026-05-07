# frozen_string_literal: true

class Shrine
  module Plugins
    module ValidatePdfIntegrity
      module AttacherMethods
        def validate_pdf_integrity
          return unless get.mime_type == Mime[:pdf].to_s

          get.download do |file|
            reader = PDF::Reader.new(file)

            if reader.page_count < 1
              log_rejection('empty_pdf')
              errors << I18n.t('errors.messages.uploads.pdf.invalid')
              break
            end

            reader.pages.each(&:raw_content)
          end
        rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError,
               PDF::Reader::EncryptedPDFError, Zlib::DataError, Zlib::BufError => e
          log_rejection(e.class.name.demodulize.underscore, e.message)
          errors << I18n.t('errors.messages.uploads.malformed_pdf')
        rescue => e
          log_rejection('unexpected_error', "#{e.class}: #{e.message}")
          errors << I18n.t('errors.messages.uploads.malformed_pdf')
        end

        private

        def log_rejection(reason, detail = nil)
          Rails.logger.warn(
            'validate_pdf_integrity rejected file',
            reason:,
            detail:,
            file_size: get.size
          )
        end
      end
    end

    register_plugin(:validate_pdf_integrity, ValidatePdfIntegrity)
  end
end
