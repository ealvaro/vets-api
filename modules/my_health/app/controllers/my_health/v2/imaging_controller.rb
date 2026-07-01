# frozen_string_literal: true

require 'unified_health_data/imaging_service'
require 'unified_health_data/serializers/imaging_study_serializer'
require 'sidekiq/api'

module MyHealth
  module V2
    ##
    # V2 controller for medical imaging studies served through the Unified Health
    # Data (UHD) imaging service.
    #
    # Lists imaging studies (filtered by date, type, and the user's resolved
    # site IDs), returns per-study thumbnails and DICOM zip metadata, and proxies
    # thumbnail images from presigned S3 URLs (validated against an allowlist to
    # prevent SSRF). Enqueues a background imaging refresh job on +index+.
    #
    class ImagingController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'
      before_action :enqueue_imaging_refresh_job, only: :index

      ##
      # Lists the current user's imaging studies, optionally sorted.
      #
      # @return [JSON] serialized imaging studies
      #
      def index
        imaging_studies = sort_records(
          service.get_imaging_studies(
            start_date: params[:start_date],
            end_date: params[:end_date],
            imaging_study_type: params[:imaging_study_type].presence || 'RADIOLOGY',
            site_ids: user_site_ids,
            no_cache: no_cache_requested?
          ),
          params[:sort]
        )
        serialized_studies = UnifiedHealthData::Serializers::ImagingStudySerializer
                             .new(imaging_studies).serializable_hash[:data]

        render json: serialized_studies, status: :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'imaging studies', api_type: 'FHIR')
      end

      ##
      # Returns thumbnail data for a single imaging study.
      #
      # @return [JSON] serialized imaging study thumbnails
      #
      def thumbnails
        # NOTE: params[:id] is a FHIR imaging study identifier URN (e.g. 'urn-vastudy-...')
        record_id = params[:id]

        imaging_studies = service.get_imaging_study(
          start_date: default_start_date,
          end_date: default_end_date,
          record_id:
        )
        serialized_studies = UnifiedHealthData::Serializers::ImagingStudySerializer.new(imaging_studies).serializable_hash[:data]

        render json: serialized_studies,
               status: :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'imaging study', api_type: 'FHIR')
      end

      ##
      # Returns DICOM zip metadata for a single imaging study.
      #
      # @return [JSON] serialized imaging study DICOM data
      #
      def dicom
        # NOTE: params[:id] is a FHIR imaging study identifier URN (e.g. 'urn-vastudy-...')
        record_id = params[:id]

        imaging_studies = service.get_dicom_zip(
          start_date: default_start_date,
          end_date: default_end_date,
          record_id:
        )
        serialized_studies = UnifiedHealthData::Serializers::ImagingStudySerializer.new(imaging_studies).serializable_hash[:data]

        render json: serialized_studies,
               status: :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'DICOM zip', api_type: 'FHIR')
      end

      ##
      # Proxies a thumbnail image from S3 through vets-api so the browser can load it
      # without requiring a CSP change for the S3 bucket domain.
      #
      # The frontend passes the presigned S3 URL (obtained from the `thumbnails` action)
      # as a query parameter. This action validates the URL domain against an allowlist
      # to prevent SSRF, fetches the image, and streams it back as binary JPEG.
      #
      # GET /my_health/v2/medical_records/imaging/thumbnail_proxy?url=<encoded_presigned_url>
      #
      def thumbnail_proxy
        url = params[:url]
        raise Common::Exceptions::ParameterMissing, 'url' if url.blank?

        uri = URI.parse(url)
        validate_s3_url!(uri)

        buffer_from_s3(uri)
      rescue URI::InvalidURIError
        render_error('Bad Request', 'Invalid URL format', '400', 400, :bad_request)
      rescue Common::Exceptions::ParameterMissing => e
        raise e
      rescue SecurityError
        Rails.logger.warn("Thumbnail proxy SSRF blocked for host: #{uri&.host}")
        render_error('Forbidden', 'URL not allowed', '403', 403, :forbidden)
      rescue => e
        handle_error(e, resource_name: 'thumbnail image', api_type: 'S3')
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
      # Buffers thumbnail image data from a presigned S3 URL into memory and renders it.
      # The entire image is held in memory before being sent to the client.
      #
      # @param uri [URI] the parsed presigned URL
      #
      def buffer_from_s3(uri)
        image_data = nil

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

            image_data = http_response.read_body
          end
        end

        response.headers['Cache-Control'] = 'private, max-age=3600'
        send_data(image_data, type: 'image/jpeg', disposition: 'inline')
      end

      def service
        @service ||= UnifiedHealthData::ImagingService.new(@current_user)
      end

      def no_cache_requested?
        ActiveModel::Type::Boolean.new.cast(params[:no_cache]) || false
      end

      # SCDF requires date params for thumbnails and DICOM but they do not
      # affect results. Provide a wide window so every study qualifies.
      def default_start_date
        10.years.ago.strftime('%Y-%m-%d')
      end

      def default_end_date
        Time.zone.today.strftime('%Y-%m-%d')
      end

      # Combines the user's VistA treatment facility IDs and Oracle Health indicator
      # to build the full list of sites for SCDF imaging queries.
      # SCDF expects the sentinel value '200CRNR' when a user has any Cerner-transitioned
      # facilities, rather than individual Cerner station numbers.
      ORACLE_HEALTH_SITE_ID = '200CRNR'

      def user_site_ids
        vista_ids = @current_user.va_treatment_facility_ids || []
        cerner_ids = @current_user.cerner_facility_ids || []
        site_ids = vista_ids.map(&:to_s)
        site_ids << ORACLE_HEALTH_SITE_ID if cerner_ids.present?
        site_ids.uniq!

        log_site_id_breakdown(vista_ids, cerner_ids, site_ids)

        if site_ids.empty?
          Rails.logger.warn(
            message: 'ImagingController#user_site_ids resolved to empty site_ids',
            icn: @current_user.icn
          )
        end

        site_ids
      end

      def log_site_id_breakdown(vista_ids, cerner_ids, site_ids)
        return unless Flipper.enabled?(:mhv_medical_records_imaging_site_id_logging, @current_user)

        cerner_in_vista = vista_ids.map(&:to_s) & cerner_ids.map(&:to_s)
        Rails.logger.info(
          message: 'ImagingController#user_site_ids facility breakdown',
          vista_ids: vista_ids.map(&:to_s),
          cerner_ids: cerner_ids.map(&:to_s),
          cerner_in_vista_ids: cerner_in_vista,
          number_overlap: cerner_in_vista.size,
          final_site_ids: site_ids
        )
      end

      def enqueue_imaging_refresh_job
        if Flipper.enabled?(:mhv_accelerated_delivery_uhd_oh_imaging_logging_enabled, @current_user) ||
           Flipper.enabled?(:mhv_accelerated_delivery_uhd_vista_imaging_logging_enabled, @current_user)
          Rails.logger.info('UHD ImagingRefreshJob enqueue attempt', user_uuid: @current_user&.uuid)
          UnifiedHealthData::ImagingRefreshJob.perform_async(@current_user.uuid, user_site_ids)
        else
          Rails.logger.info('UHD ImagingRefreshJob skipped - toggles disabled', user_uuid: @current_user&.uuid)
        end
      rescue => e
        Rails.logger.error('UHD ImagingRefreshJob enqueue failed', error: e.message, class: e.class.name)
      end
    end
  end
end
