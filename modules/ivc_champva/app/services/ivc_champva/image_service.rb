# frozen_string_literal: true

require 'datadog'

module IvcChampva
  ##
  # Facade for image/file transformations applied to CHAMPVA supporting-document
  # uploads. It wraps the lower-level transformers (currently IvcChampva::ImageResizer)
  # and owns the observability + failure-handling around them, so the uploads
  # controller can stay thin and image handling is centralized and testable.
  #
  # TODO: Migrate image-origin transforms out of
  # IvcChampva::V1::UploadsController so they share monitoring and a single call
  # site:
  #   - Image -> PDF conversion on upload: move UploadsController#convert_to_pdf
  #     here (it wraps IvcChampva::PdfConverter), gated by
  #     :champva_convert_to_pdf_on_upload.
  #
  # If we later want a single orchestration point for all supporting-document
  # prep (unlock -> resize -> convert), introduce a thin document/attachment
  # preparer that composes this service rather than widening ImageService.
  class ImageService
    ##
    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to transform
    # @param form_id [String] The government form ID (e.g., '10-10D'), used for metrics
    # @param monitor [IvcChampva::Monitor] Observability sink (injectable for tests)
    def initialize(uploaded_file, form_id, monitor: IvcChampva::Monitor.new)
      @uploaded_file = uploaded_file
      @form_id = form_id
      @monitor = monitor
    end

    ##
    # Downscales oversized image uploads to the uploader's supported dimensions.
    # On failure, the derived context plus the error class is logged and the
    # original file is returned so normal attachment validation still runs (an
    # oversized image then fails as it does today).
    #
    # @return [ActionDispatch::Http::UploadedFile] The original or resized file
    def resize_if_needed
      Datadog::Tracing.trace('IVC Champva Forms - Resize Image') do
        resizer = IvcChampva::ImageResizer.new(@uploaded_file)
        next @uploaded_file if resizer.valid?

        context = resize_context(resizer)
        resized = resizer.resize
        @monitor.track_image_resize(@form_id, 'resized', context)
        resized
      rescue => e
        @monitor.track_image_resize(@form_id, 'error', (context || {}).merge(error_class: e.class.name))
        @uploaded_file
      end
    end

    private

    def resize_context(resizer)
      width, height = resizer.original_dimensions
      { original_width: width, original_height: height, content_type: resizer.content_type }
    end
  end
end
