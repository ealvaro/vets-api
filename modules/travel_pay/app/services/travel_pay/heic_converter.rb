# frozen_string_literal: true

require 'mini_magick'
require 'base64'

module TravelPay
  ##
  # Converts HEIC/HEIF images to JPG format.
  #
  class HeicConverter
    include Monitorable

    # @param user [User] the current user for feature flag checks
    def initialize(user)
      @user = user
    end

    # Processes expense params and converts HEIC receipt to JPG if present
    #
    # @param params [Hash] expense params hash that may contain an 'expenseReceipt' key
    # @return [Hash] params with receipt converted to JPG if it was HEIC/HEIF
    # @raise [Common::Exceptions::UnprocessableEntity] if conversion fails
    def convert_if_heic(params)
      receipt = params['expenseReceipt']
      return params unless receipt.present? && heic_image?(receipt['contentType'])

      unless Flipper.enabled?(:travel_pay_enable_heic_conversion, @user)
        monitor.log(:warn, 'Unsupported HEIC/HEIF receipt rejected')
        raise Common::Exceptions::UnprocessableEntity.new(
          detail: 'HEIC/HEIF images are not currently supported. Please convert to JPG or PNG before uploading.'
        )
      end

      monitor.log(:info, 'Converting HEIC receipt to JPG')

      converted_receipt = convert_heic_to_jpg(receipt)
      params.merge('expenseReceipt' => converted_receipt)
    rescue Common::Exceptions::UnprocessableEntity
      raise
    rescue => e
      error_message = "HEIC conversion failed: #{e.class} - #{e.message}"
      monitor.track_request(:error, error_message, 'travel_pay.heic_converter.receipt_conversion_failed')
      raise Common::Exceptions::UnprocessableEntity.new(detail: error_message)
    end

    # Converts an uploaded HEIC/HEIF file to a JPG uploaded file.
    # Yields the converted file to the block; the underlying tempfile is
    # automatically closed and deleted when the block returns.
    #
    # @param uploaded_file [ActionDispatch::Http::UploadedFile] the uploaded HEIC/HEIF file
    # @yield [ActionDispatch::Http::UploadedFile] the converted JPG file
    # @raise [Common::Exceptions::UnprocessableEntity] if conversion fails
    def convert_file_to_jpg(uploaded_file)
      monitor.log(:info, 'Converting HEIC document upload to JPG')

      jpg_binary = convert_image_to_jpg(uploaded_file.read)

      converted_tempfile = Tempfile.new(['converted', '.jpg'])
      converted_tempfile.binmode
      converted_tempfile.write(jpg_binary)
      converted_tempfile.rewind

      converted_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: converted_tempfile,
        filename: uploaded_file.original_filename.sub(/\.hei[cf]$/i, '.jpg'),
        type: 'image/jpeg'
      )

      yield converted_file
    rescue Common::Exceptions::UnprocessableEntity
      raise
    rescue => e
      error_message = "HEIC conversion failed: #{e.class} - #{e.message}"
      monitor.track_request(:error, error_message, 'travel_pay.heic_converter.file_conversion_failed')
      raise Common::Exceptions::UnprocessableEntity.new(detail: error_message)
    end

    private

    # Checks if the content type is HEIC/HEIF format
    #
    # @param content_type [String, nil] the content type to check
    # @return [Boolean] true if content type is HEIC/HEIF
    def heic_image?(content_type)
      content_type.to_s.match?(%r{^image/(heic|heif)$}i)
    end

    # Converts a HEIC receipt hash to JPG format
    #
    # @param receipt [Hash] receipt hash with camelCase keys (contentType, fileData, etc.)
    # @return [Hash] updated receipt hash with JPG data
    def convert_heic_to_jpg(receipt)
      file_data = receipt['fileData']
      return receipt if file_data.blank?

      jpg_binary = convert_image_to_jpg(Base64.strict_decode64(file_data))

      receipt.merge(
        'fileData' => Base64.strict_encode64(jpg_binary),
        'contentType' => 'image/jpeg',
        'length' => jpg_binary.bytesize.to_s,
        'fileName' => receipt['fileName']&.sub(/\.hei[cf]$/i, '.jpg')
      ).tap do
        monitor.log(:info, "Successfully converted HEIC to JPG (size: #{jpg_binary.bytesize} bytes)")
      end
    end

    # Converts binary image data to JPG format using MiniMagick
    #
    # @param binary_data [String] binary image data
    # @return [String] JPG binary data
    def convert_image_to_jpg(binary_data)
      image = nil
      Tempfile.create(['receipt', '.heic']) do |file|
        file.binmode
        file.write(binary_data)
        file.flush

        image = MiniMagick::Image.open(file.path)
        image.format('jpg')

        File.binread(image.path)
      ensure
        image&.destroy! if defined?(image) && image
      end
    end
  end
end
