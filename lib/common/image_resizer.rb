# frozen_string_literal: true

require 'mini_magick'

module Common
  ##
  # Downscales oversized image uploads to a bounded geometry target.
  # Non-image files (e.g. PDFs, Word docs) are treated as already valid and
  # are never touched.
  class ImageResizer
    attr_reader :uploaded_file, :max_width, :max_height, :tempfile_prefix

    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to inspect/resize
    # @param max_width [Integer] Maximum allowed width in pixels
    # @param max_height [Integer] Maximum allowed height in pixels
    # @param tempfile_prefix [String] Prefix used for the resized file's Tempfile name
    def initialize(uploaded_file, max_width:, max_height:, tempfile_prefix: 'resized_')
      @uploaded_file = uploaded_file
      @max_width = max_width
      @max_height = max_height
      @tempfile_prefix = tempfile_prefix
    end

    ##
    # Content type of the wrapped upload. Nil-safe so this transformer never
    # raises on an unexpected input; a nil content type simply reads as "not
    # an image" and the file is left untouched.
    #
    # @return [String, nil]
    def content_type
      uploaded_file.try(:content_type)
    end

    ##
    # Whether the file needs no resize. True for non-images (passed through
    # untouched) and for images already within the dimension bounds; false only
    # for an image that exceeds max_width or max_height.
    #
    # @return [Boolean]
    def valid?
      return true unless image?

      width, height = original_dimensions
      return true if width.nil? || height.nil?

      width <= max_width && height <= max_height
    end

    ##
    # Downscales the image (aspect-ratio preserving, shrink-only) to fit within
    # max_width x max_height and returns a new uploaded file with the same
    # filename and content type. The original format is preserved.
    #
    # @return [ActionDispatch::Http::UploadedFile] The resized file
    def resize
      image = MiniMagick::Image.open(source_path)
      # The trailing '>' only shrinks images larger than the given geometry and
      # preserves aspect ratio; smaller images are left unchanged.
      image.resize "#{max_width}x#{max_height}>"

      tempfile = Tempfile.new([tempfile_prefix, File.extname(original_filename)])
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
      uploaded_file.original_filename
    end

    def source_path
      tempfile = uploaded_file.tempfile if uploaded_file.respond_to?(:tempfile)
      return tempfile.path if tempfile.respond_to?(:path)

      uploaded_file.path
    end
  end
end
