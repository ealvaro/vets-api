# frozen_string_literal: true

require 'common/image_resizer'

module IvcChampva
  ##
  # Downscales oversized image uploads so they fit within the dimension bounds
  # enforced by ClaimDocumentation::Uploader's attachment validation. Non-image
  # files (e.g. PDFs) are treated as already valid and are never touched.
  class ImageResizer < Common::ImageResizer
    MAX_WIDTH = ClaimDocumentation::Uploader::MAX_IMAGE_WIDTH
    MAX_HEIGHT = ClaimDocumentation::Uploader::MAX_IMAGE_HEIGHT

    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to inspect/resize
    def initialize(uploaded_file)
      super(uploaded_file, max_width: MAX_WIDTH, max_height: MAX_HEIGHT, tempfile_prefix: 'ivc_champva_resized_')
    end
  end
end
