# frozen_string_literal: true

module IvcChampva
  class PdfConverter
    def initialize(uploaded_file)
      @uploaded_file = uploaded_file
    end

    ##
    # Converts an uploaded file to PDF format using ImageMagick.
    # When auto-resize is enabled, uses JPEG compression to prevent raw-pixel
    # inflation for formats like HEIC where decompressed pixel data can exceed
    # validation limits. Otherwise delegates to the shared Common::ConvertToPdf.
    #
    # @return [String] Path to the converted PDF file
    def convert_to_pdf
      # Only image uploads with auto-resize enabled get JPEG-compressed conversion;
      # PDFs and the flag-off path delegate to the shared converter.
      unless Flipper.enabled?(:champva_auto_resize_on_upload) && @uploaded_file.content_type != 'application/pdf'
        return Common::ConvertToPdf.new(@uploaded_file).run
      end

      in_file = Common::FileHelpers.generate_clamav_temp_file(@uploaded_file.read)
      out_file = "#{Common::FileHelpers.random_file_path}.pdf"

      begin
        convert_and_compress(in_file, out_file)
      rescue => e
        handle_conversion_error(e)
      ensure
        FileUtils.rm_f(in_file)
      end
    end

    ##
    # Converts an uploaded file to PDF format using ImageMagick.
    # Returns a Tempfile with the PDF contents, ready for use.
    #
    # @return [Tempfile] Tempfile containing the converted PDF, in binmode and rewound
    def convert_to_tempfile
      pdf_path = convert_to_pdf
      pdf_filename = @uploaded_file.original_filename.sub(/\.[^.]+\z/, '.pdf')

      tempfile = Tempfile.new([File.basename(pdf_filename, '.pdf'), '.pdf'])
      tempfile.binmode
      tempfile.write(File.read(pdf_path))
      tempfile.rewind

      tempfile
    ensure
      FileUtils.rm_f(pdf_path) if pdf_path && File.exist?(pdf_path)
    end

    private

    # A HEIC file with an unsupported internal codec is a client problem, not a
    # server error, so surface it as a 422; everything else bubbles up as-is.
    def handle_conversion_error(error)
      if error.is_a?(MiniMagick::Error) && error.message.include?('Unsupported feature')
        Rails.logger.warn("IVC ChampVA PDF conversion rejected unsupported HEIC codec: #{error.message}")
        raise Common::Exceptions::UnprocessableEntity.new(
          detail: 'This HEIC file uses an unsupported codec. Please convert to JPEG or PNG before uploading.'
        )
      end

      Rails.logger.error("IVC ChampVA Forms - Failed to convert file to PDF: #{error.message}")
      raise error
    end

    def convert_and_compress(in_file, out_file)
      MiniMagick.convert do |convert|
        convert << '-units' << 'pixelsperinch' << '-density' << '72' << '-page' << 'letter'
        convert << '-compress' << 'jpeg' << '-quality' << '85'
        convert << in_file
        convert << out_file
      end

      out_file
    end
  end
end
