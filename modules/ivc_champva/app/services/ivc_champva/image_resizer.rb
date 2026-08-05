# frozen_string_literal: true

require 'mini_magick'

module IvcChampva
  ##
  # Downscales oversized image uploads so they fit within the dimension bounds
  # enforced by ClaimDocumentation::Uploader's attachment validation. Non-image
  # files (e.g. PDFs) are treated as already valid and are never touched.
  class ImageResizer
    MAX_WIDTH = ClaimDocumentation::Uploader::MAX_IMAGE_WIDTH
    MAX_HEIGHT = ClaimDocumentation::Uploader::MAX_IMAGE_HEIGHT

    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to inspect/resize
    def initialize(uploaded_file)
      @uploaded_file = uploaded_file
    end

    ##
    # Content type of the wrapped upload. The upload flow always hands us an
    # UploadedFile, but we stay nil-safe here so this transformer never raises on
    # an unexpected input; a nil content type simply reads as "not an image" and
    # the file is left untouched.
    #
    # @return [String, nil]
    def content_type
      @uploaded_file.try(:content_type)
    end

    ##
    # Whether the file needs no resize. True for non-images (passed through
    # untouched) and for images already within the dimension bounds; false only
    # for an image that exceeds MAX_WIDTH or MAX_HEIGHT.
    #
    # @return [Boolean]
    def valid?
      return true unless image?

      width, height = original_dimensions
      return true if width.nil? || height.nil?

      width <= MAX_WIDTH && height <= MAX_HEIGHT
    end

    ##
    # Downscales the image (aspect-ratio preserving, shrink-only) to fit within
    # MAX_WIDTH x MAX_HEIGHT and returns a new uploaded file with the same
    # filename and content type. The original format is preserved.
    #
    # @return [ActionDispatch::Http::UploadedFile] The resized file
    def resize
      image = MiniMagick::Image.open(source_path)
      # The trailing '>' only shrinks images larger than the given geometry and
      # preserves aspect ratio; smaller images are left unchanged.
      # Example: 6000x8000 scale factor = min(5616/6000, 7272/8000)
      # = min(0.936, 0.909) = 0.909 → result 5454x7272
      image.resize "#{MAX_WIDTH}x#{MAX_HEIGHT}>"

      tempfile = Tempfile.new(['ivc_champva_resized_', File.extname(original_filename)])
      tempfile.binmode
      # Stream the resized bytes straight from MiniMagick into the tempfile
      # rather than buffering the whole image into memory.
      image.write(tempfile)
      tempfile.rewind

      ActionDispatch::Http::UploadedFile.new(
        tempfile:,
        filename: original_filename,
        type: content_type
      )
    end

    ##
    # Original [width, height] of the image, or [nil, nil] if unreadable or not
    # an image. Memoized so valid? and logging don't re-open the file.
    #
    # @return [Array(Integer, Integer), Array(nil, nil)]
    def original_dimensions
      @original_dimensions ||= if image?
                                 MiniMagick::Image.open(source_path).dimensions
                               else
                                 [nil, nil]
                               end
    rescue MiniMagick::Error
      [nil, nil]
    end

    private

    def image?
      content_type.to_s.start_with?('image/')
    end

    def original_filename
      @uploaded_file.original_filename
    end

    def source_path
      if @uploaded_file.respond_to?(:tempfile)
        @uploaded_file.tempfile.path
      else
        @uploaded_file.path
      end
    end
  end
end
