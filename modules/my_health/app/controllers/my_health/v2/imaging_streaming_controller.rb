# frozen_string_literal: true

module MyHealth
  module V2
    ##
    # Separate controller for streaming thumbnail images via ActionController::Live.
    # This isolates ActionController::Live to only this controller to avoid potential
    # interference with authorization middleware on other imaging endpoints.
    #
    class ImagingStreamingController < ApplicationController
      include ActionController::Live
      include MyHealth::V2::Concerns::ErrorHandler
      service_tag 'mhv-medical-records'

      ##
      # Proxies a thumbnail image from S3 through vets-api via streaming.
      # Each chunk is written to the response stream as it arrives, so the full
      # image is never held in process memory.
      #
      # GET /my_health/v2/medical_records/imaging/thumbnail_proxy_stream?url=<encoded_presigned_url>
      #
      def thumbnail_proxy
        url = params[:url]
        raise Common::Exceptions::ParameterMissing, 'url' if url.blank?

        uri = URI.parse(url)
        validate_s3_url!(uri)

        stream_from_s3(uri)
      rescue URI::InvalidURIError
        render_error('Bad Request', 'Invalid URL format', '400', 400, :bad_request)
      rescue Common::Exceptions::ParameterMissing => e
        raise e
      rescue SecurityError
        Rails.logger.warn("Thumbnail proxy SSRF blocked for host: #{uri&.host}")
        render_error('Forbidden', 'URL not allowed', '403', 403, :forbidden)
      rescue => e
        if response.committed?
          Rails.logger.error('Error while streaming thumbnail image', exception: e)
        else
          handle_error(e, resource_name: 'thumbnail image', api_type: 'S3')
        end
      ensure
        response.stream.close if response.committed?
      end

      private

      # Allowlist of S3 host patterns for thumbnail images.
      # Matches only known CVIX thumbnail buckets in the us-gov-west-1 region.
      # Buckets: mhv-di-5-cvix-thumbnails, mhv-intb-cvix-thumbnails,
      #          mhv-sysb-cvix-thumbnails, mhv-pr-cvix-thumbnails

      ALLOWED_S3_HOST_PATTERN = /\Amhv-(?:di-5|intb|sysb|pr)-cvix-thumbnails\.s3[.-]us-gov-west-1\.amazonaws\.com\z/i

      ##
      # Validates that the given URI points to an allowed S3 host.
      # Raises SecurityError if the host does not match the allowlist.
      #
      # @param uri [URI] the parsed URI to validate
      # @raise [SecurityError] if the host is not an allowed S3 domain
      #
      def validate_s3_url!(uri)
        unless uri.scheme == 'https' && ALLOWED_S3_HOST_PATTERN.match?(uri.host)
          raise SecurityError, "Disallowed host: #{uri.host}"
        end
      end

      ##
      # Streams image data from a presigned URL directly to the client.
      # Each chunk is written to the response stream as it arrives, so the full
      # image is never held in process memory.
      #
      # @param uri [URI] the parsed presigned URL
      #
      def stream_from_s3(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10,
                                            read_timeout: 30) do |http|
          request = Net::HTTP::Get.new(uri.request_uri)

          http.request(request) do |http_response|
            unless http_response.is_a?(Net::HTTPSuccess)
              Rails.logger.error("Failed to fetch thumbnail: HTTP #{http_response.code}")
              raise Common::Exceptions::BackendServiceException.new(
                'MR_THUMBNAIL_FETCH_ERROR', {}, http_response.code.to_i
              )
            end

            # Set response headers only after confirming S3 returned success,
            # so error handlers can still render a proper JSON error response.
            response.headers['Content-Type'] = 'image/jpeg'
            response.headers['Content-Disposition'] = 'inline'
            response.headers['Cache-Control'] = 'private, max-age=3600'

            http_response.read_body do |chunk|
              response.stream.write(chunk)
            end
          end
        end
      end
    end
  end
end
