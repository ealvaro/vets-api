# frozen_string_literal: true

require 'common/image_resize_service'
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
  class ImageService < Common::ImageResizeService
    ##
    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to transform
    # @param form_id [String] The government form ID (e.g., '10-10D'), used for metrics
    # @param monitor [IvcChampva::Monitor] Observability sink (injectable for tests)
    def initialize(uploaded_file, form_id, monitor: IvcChampva::Monitor.new)
      super(uploaded_file, resizer_class: IvcChampva::ImageResizer)
      @form_id = form_id
      @monitor = monitor
    end

    private

    def instrument(&)
      Datadog::Tracing.trace('IVC Champva Forms - Resize Image', &)
    end

    def track_success(context)
      @monitor.track_image_resize(@form_id, 'resized', context)
    end

    def track_error(context)
      @monitor.track_image_resize(@form_id, 'error', context)
    end
  end
end
