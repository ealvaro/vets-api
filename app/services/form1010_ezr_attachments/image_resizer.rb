# frozen_string_literal: true

require 'common/image_resizer'

module Form1010EzrAttachments
  ##
  # Downscales oversized image uploads to a bounded geometry target.
  # Non-image files (e.g. PDFs, Word docs) are treated as already valid and
  # are never touched.
  class ImageResizer < Common::ImageResizer
    MAX_WIDTH = 5616
    MAX_HEIGHT = 7272

    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to inspect/resize
    def initialize(uploaded_file)
      super(uploaded_file, max_width: MAX_WIDTH, max_height: MAX_HEIGHT, tempfile_prefix: 'hca_ezr_resized_')
    end
  end
end
