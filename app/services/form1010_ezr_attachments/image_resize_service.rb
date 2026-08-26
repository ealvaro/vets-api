# frozen_string_literal: true

require 'common/image_resize_service'
require 'form1010_ezr/service'

module Form1010EzrAttachments
  ##
  # Facade for image transformations applied to 10-10EZ/EZR attachment
  # uploads. Wraps Form1010EzrAttachments::ImageResizer and owns the
  # observability + failure-handling around it, gated behind
  # :hca_auto_resize_on_upload.
  class ImageResizeService < Common::ImageResizeService
    STATSD_KEY_PREFIX = "#{Form1010Ezr::Service::STATSD_KEY_PREFIX}.attachments.image_resize".freeze

    # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to transform
    def initialize(uploaded_file)
      super(uploaded_file, resizer_class: Form1010EzrAttachments::ImageResizer)
    end

    private

    def rescued_errors
      [MiniMagick::Error, Errno::ENOENT, Errno::EACCES]
    end

    def error_attributes(error)
      super.merge(error_message: error.message)
    end

    def track_success(context)
      track('resized', context)
    end

    def track_error(context)
      track('error', context)
    end

    def track(decision, context)
      StatsD.increment("#{STATSD_KEY_PREFIX}.#{decision}")

      log_method = decision == 'error' ? :warn : :info
      Rails.logger.public_send(
        log_method,
        "[Form1010EzrAttachments] image resize #{decision}",
        context
      )
    end
  end
end
