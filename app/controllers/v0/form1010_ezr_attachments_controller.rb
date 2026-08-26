# frozen_string_literal: true

require 'form1010_ezr/service'
require 'benchmark'

module V0
  class Form1010EzrAttachmentsController < ApplicationController
    include FormAttachmentCreate
    service_tag 'health-information-update'

    FORM_ATTACHMENT_MODEL = Form1010EzrAttachment

    def create
      validate_file_upload_class!

      resize_image_if_needed!

      Form1010EzrAttachments::FileTypeValidator.new(
        filtered_params['file_data']
      ).validate

      save_attachment_to_cloud!
      save_attachment_to_db!

      render json: serializer_klass.new(form_attachment)
    end

    private

    def resize_image_if_needed!
      return unless Flipper.enabled?(:hca_auto_resize_on_upload, current_user)

      filtered_params['file_data'] = Form1010EzrAttachments::ImageResizeService.new(
        filtered_params['file_data']
      ).resize_if_needed
    end

    def serializer_klass
      Form1010EzrAttachmentSerializer
    end
  end
end
