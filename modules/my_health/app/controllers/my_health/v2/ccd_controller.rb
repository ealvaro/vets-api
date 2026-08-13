# frozen_string_literal: true

require 'unified_health_data/ccd_service'
require 'unified_health_data/serializers/ccd_serializer'

module MyHealth
  module V2
    ##
    # V2 controller for Continuity of Care Document (CCD) generation, status
    # polling, and download.
    #
    # Generation and status are served through the Unified Health Data (UHD) CCD
    # service. Download fetches the document from a presigned S3 URL, validated
    # against an allowlist to prevent SSRF, and supports XML, HTML, and PDF.
    #
    class CcdController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      service_tag 'mhv-medical-records'

      before_action :verify_ccd_ownership!, only: %i[status download]

      ##
      # Initiates generation of a CCD for the current user.
      #
      # @return [JSON] serialized CCD job; 200 OK when already complete,
      #   otherwise 202 Accepted
      #
      def generate
        ccd = service.initiate_ccd
        remember_ccd_job_owner(ccd.job_id)
        http_status = ccd.http_status == 200 ? :ok : :accepted
        render json: UnifiedHealthData::Serializers::CcdSerializer.new(ccd).serializable_hash, status: http_status
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'CCD', api_type: 'SCDF')
      end

      ##
      # Returns the status of a CCD generation job.
      #
      # @return [JSON] serialized CCD job; 200 OK when complete, otherwise 202 Accepted
      #
      def status
        job_id = params[:job_id]
        ccd = service.get_ccd_status(job_id:)
        http_status = ccd.http_status == 200 ? :ok : :accepted
        render json: UnifiedHealthData::Serializers::CcdSerializer.new(ccd).serializable_hash, status: http_status
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'CCD', api_type: 'SCDF')
      end

      ##
      # Downloads the generated CCD in the requested format from S3.
      #
      # @return [void] sends the CCD document as an attachment (XML, HTML, or PDF)
      #
      def download
        file_format = params[:format] || 'xml'
        presigned_url = resolve_presigned_url!(file_format)
        body = fetch_ccd_from_s3(presigned_url)

        content_type = CCD_CONTENT_TYPES[file_format] || 'application/octet-stream'
        send_data body,
                  type: content_type,
                  disposition: 'attachment',
                  status: :ok
      rescue Common::Exceptions::RecordNotFound
        render_error('CCD Not Found', 'The requested CCD format is not available', '404', 404, :not_found)
      rescue URI::InvalidURIError
        render_error('Bad Request', 'Invalid presigned URL format', '400', 400, :bad_request)
      rescue SecurityError => e
        Rails.logger.warn("CCD download SSRF blocked: #{e.message}")
        render_error('Forbidden', 'URL not allowed', '403', 403, :forbidden)
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'CCD', api_type: 'S3')
      end

      private

      # Numeric = correlated Task id (enumerable), checked against the user's own jobs list.
      NUMERIC_TASK_ID = /\A\d+\z/
      # Pre-correlation job id shape; ownership is established at generation time (see below).
      UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
      CCD_JOB_OWNER_CACHE_PREFIX = 'uhd:ccd_job_owner:'
      CCD_JOB_OWNER_TTL = 1.hour

      ##
      # Rejects requests for a CCD job the current user does not own.
      #
      # Numeric task ids (enumerable) are verified against the user's own CCD jobs
      # (scoped to +current_user.icn+ upstream). Pre-correlation UUID job ids are not yet in
      # that list, so ownership is verified against the mapping recorded at generation time.
      # Any other id shape is rejected.
      #
      # @return [void] renders 404 and halts the request when ownership fails
      #
      def verify_ccd_ownership!
        job_id = params[:job_id]

        if job_id&.match?(NUMERIC_TASK_ID)
          owned_ids = owned_ccd_job_ids
          return if performed? # get_ccd_jobs failed and already rendered an error
          return if owned_ids.include?(job_id)
        elsif job_id&.match?(UUID_FORMAT)
          return if ccd_job_owner(job_id) == @current_user.icn
        end

        render_error('CCD Not Found', 'The requested CCD is not available', '404', 404, :not_found)
      end

      # @return [Array<String>] the current user's CCD job/task ids
      def owned_ccd_job_ids
        service.get_ccd_jobs.flat_map { |ccd| [ccd.job_id, ccd.task_id] }.compact.uniq
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'CCD', api_type: 'SCDF')
        []
      end

      # Records the pre-correlation UUID job id against the requesting user so ownership can be
      # verified before the job appears in the ICN-scoped jobs list. Best-effort: a cache failure
      # must not break generation.
      def remember_ccd_job_owner(job_id)
        return if job_id.blank?

        Rails.cache.write("#{CCD_JOB_OWNER_CACHE_PREFIX}#{job_id}", @current_user.icn,
                          expires_in: CCD_JOB_OWNER_TTL)
      rescue => e
        Rails.logger.warn("CCD job owner cache write failed: #{e.class}")
      end

      # @return [String, nil] the ICN that generated the given job id, if still cached
      def ccd_job_owner(job_id)
        Rails.cache.read("#{CCD_JOB_OWNER_CACHE_PREFIX}#{job_id}")
      end

      ##
      # Resolves and validates a presigned S3 URL for the requested CCD format.
      #
      # @param file_format [String] the CCD format ('xml', 'html', or 'pdf')
      # @return [String] a validated presigned S3 URL
      # @raise [Common::Exceptions::RecordNotFound] if no URL is available for the format
      # @raise [SecurityError] if the URL host is not on the allowlist
      # @raise [URI::InvalidURIError] if the URL is malformed
      #
      def resolve_presigned_url!(file_format)
        presigned_url = service.get_ccd_url(job_id: params[:job_id], format: file_format)

        if presigned_url.nil?
          raise Common::Exceptions::RecordNotFound.new('CCD', detail: 'The requested CCD format is not available')
        end

        uri = URI.parse(presigned_url)
        validate_s3_url!(uri)
        presigned_url
      end

      # Content types for each CCD format
      CCD_CONTENT_TYPES = {
        'xml' => 'application/xml',
        'html' => 'text/html',
        'pdf' => 'application/pdf'
      }.freeze

      # Allowlist of S3 host patterns for CCD documents.
      # Matches known UHD document store buckets in the us-gov-west-1 region.
      ALLOWED_CCD_S3_HOST_PATTERN = /\Amhv-[\w-]+-uhd-docstore\.s3[.-]us-gov-west-1\.amazonaws\.com\z/i

      ##
      # Validates that the given URI points to an allowed S3 host.
      # Raises SecurityError if the host does not match the allowlist.
      #
      # @param uri [URI] the parsed URI to validate
      # @raise [SecurityError] if the host is not an allowed S3 domain
      #
      def validate_s3_url!(uri)
        unless uri.scheme == 'https' && uri.host.present? && ALLOWED_CCD_S3_HOST_PATTERN.match?(uri.host)
          raise SecurityError, "Disallowed host: #{uri.host}"
        end
      end

      ##
      # Fetches the full CCD document body from a presigned S3 URL.
      #
      # @param presigned_url [String] the presigned S3 URL
      # @return [String] the raw document body
      # @raise [Common::Exceptions::BackendServiceException] if S3 returns a non-success status
      #
      def fetch_ccd_from_s3(presigned_url)
        uri = URI.parse(presigned_url)

        http_response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10,
                                                            read_timeout: 30) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri))
        end

        unless http_response.is_a?(Net::HTTPSuccess)
          Rails.logger.error("Failed to fetch CCD from S3: HTTP #{http_response.code}")
          raise Common::Exceptions::BackendServiceException.new(
            'MR_CCD_FETCH_ERROR', {}, http_response.code.to_i
          )
        end

        http_response.body
      end

      def service
        @service ||= UnifiedHealthData::CcdService.new(@current_user)
      end
    end
  end
end
