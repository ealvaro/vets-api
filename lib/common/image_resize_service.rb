# frozen_string_literal: true

module Common
  ##
  # Template for a facade around Common::ImageResizer subclasses. Owns the
  # shared resize-attempt/fallback flow (call resizer, track outcome, fall back
  # to the original file on failure) while letting each caller plug in its own
  # tracing, metrics, and rescued error classes.
  class ImageResizeService
    attr_reader :uploaded_file, :resizer_class

    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to transform
    # @param resizer_class [Class] A Common::ImageResizer subclass to use for the resize
    def initialize(uploaded_file, resizer_class:)
      @uploaded_file = uploaded_file
      @resizer_class = resizer_class
    end

    ##
    # Downscales oversized image uploads to the resizer's supported dimensions.
    # On failure, the derived context plus error details are tracked and the
    # original file is returned so normal attachment validation still runs.
    #
    # @return [ActionDispatch::Http::UploadedFile] The original or resized file
    def resize_if_needed
      context = {}
      instrument do
        resizer = resizer_class.new(uploaded_file)
        next uploaded_file if resizer.valid?

        context = resize_context(resizer)
        resized = resizer.resize
        track_success(context)
        resized
      end
    rescue *rescued_errors => e
      track_error(context.merge(error_attributes(e)))
      uploaded_file
    end

    private

    # Override to wrap the resize attempt (e.g. tracing). Defaults to a no-op passthrough.
    def instrument
      yield
    end

    # Override to restrict which errors trigger the fallback-to-original behavior.
    def rescued_errors
      [StandardError]
    end

    def error_attributes(error)
      { error_class: error.class.name }
    end

    def resize_context(resizer)
      width, height = resizer.original_dimensions
      { original_width: width, original_height: height, content_type: resizer.content_type }
    end

    def track_success(_context)
      raise NotImplementedError
    end

    def track_error(_context)
      raise NotImplementedError
    end
  end
end
