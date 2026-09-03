# frozen_string_literal: true

require 'marcel'
require 'open3'
require 'pdf-reader'
require 'stringio'
require 'tempfile'
require 'tmpdir'

module DocumentClassifier
  module TextExtractor
    class Error < StandardError; end
    class UnsupportedDocument < Error; end
    class DocumentTooLarge < Error; end
    class PageLimitExceeded < Error; end
    class EmptyDocument < Error; end
    class OcrFailed < Error; end

    DEFAULT_OPTIONS = { maximum_file_size: 25 * 1024 * 1024, maximum_pages: 50, maximum_characters: 100_000 }.freeze

    module_function

    def call(content, filename:, **options)
      options = DEFAULT_OPTIONS.merge(options)
      validate_content!(content, maximum_file_size: options.fetch(:maximum_file_size))
      mime_type = Marcel::MimeType.for(StringIO.new(content), name: filename)

      result = case mime_type
               when 'application/pdf'
                 extract_pdf(content, options)
               when 'text/plain'
                 build_result(content.dup.force_encoding(Encoding::UTF_8).scrub, method: 'plain_text')
               when %r{\Aimage/}
                 extract_image(content, filename:)
               else
                 raise UnsupportedDocument, "Unsupported document type: #{mime_type}"
               end

      finalize_result(result, mime_type:, maximum_characters: options.fetch(:maximum_characters))
    end

    def extract_pdf(content, options)
      with_tempfile(content, '.pdf') do |file|
        reader = PDF::Reader.new(file.path)
        page_count = reader.page_count
        maximum_pages = options.fetch(:maximum_pages)
        if page_count > maximum_pages
          raise PageLimitExceeded, "Document has #{page_count} pages; maximum is #{maximum_pages}"
        end

        embedded_text = reader.pages.filter_map(&:text).join("\n").strip
        return build_result(embedded_text, method: 'embedded', page_count:) if embedded_text.present?

        ocr_text = run_pdf_ocr(file.path, maximum_characters: options.fetch(:maximum_characters)).strip
        text = ocr_text.presence || embedded_text
        method = ocr_text.present? ? 'ocr' : 'embedded'
        build_result(text, method:, page_count:)
      end
    end

    def extract_image(content, filename:)
      extension = File.extname(filename.to_s).presence || '.img'
      with_tempfile(content, extension) do |file|
        build_result(run_ocr(file.path), method: 'ocr', page_count: 1)
      end
    end

    def run_pdf_ocr(pdf_path, maximum_characters:)
      Dir.mktmpdir('document-classifier-ocr') do |directory|
        image_prefix = File.join(directory, 'page')
        begin
          _stdout, stderr, status = Open3.capture3('pdftoppm', '-r', '200', pdf_path.to_s, image_prefix, '-png')
        rescue Errno::ENOENT => e
          raise OcrFailed, 'PDF OCR dependency is missing (pdftoppm)', cause: e
        end
        raise OcrFailed, "PDF rendering failed: #{stderr.strip}" unless status.success?

        text = +''
        page_images(image_prefix).each do |image_path|
          text << "\n" unless text.empty?
          text << run_ocr(image_path)
          break if text.length >= maximum_characters
        end
        text
      end
    end

    def run_ocr(image_path)
      begin
        stdout, stderr, status = Open3.capture3('tesseract', image_path.to_s, 'stdout')
      rescue Errno::ENOENT => e
        raise OcrFailed, 'OCR dependency is missing (tesseract)', cause: e
      end
      raise OcrFailed, "OCR failed: #{stderr.strip}" unless status.success?

      stdout.force_encoding(Encoding::UTF_8).scrub
    end

    def page_images(image_prefix)
      Dir.glob("#{image_prefix}-*.png").sort_by { |path| path.match(/-(\d+)\.png\z/)&.[](1).to_i }
    end

    def validate_content!(content, maximum_file_size:)
      raise EmptyDocument, 'Document content is empty' unless content.is_a?(String) && content.present?
      return unless content.bytesize > maximum_file_size

      raise DocumentTooLarge, "Document is #{content.bytesize} bytes; maximum is #{maximum_file_size}"
    end

    def build_result(text, method:, page_count: nil)
      { 'text' => text.to_s.strip, 'method' => method, 'page_count' => page_count }.compact
    end

    def finalize_result(result, mime_type:, maximum_characters:)
      text = result.fetch('text')
      raise EmptyDocument, 'Document extraction produced no text' if text.blank?

      original_characters = text.length
      truncated = original_characters > maximum_characters
      result.merge(
        'text' => truncated ? text.first(maximum_characters) : text,
        'mime_type' => mime_type,
        'chars' => [original_characters, maximum_characters].min,
        'original_chars' => original_characters,
        'truncated' => truncated
      )
    end

    def with_tempfile(content, extension)
      Tempfile.create(['document-classifier', extension]) do |file|
        file.binmode
        file.write(content)
        file.flush
        yield file
      end
    end
  end
end
