# frozen_string_literal: true

require_relative 'base_service'
require_relative 'adapters/ccd_adapter'

module UnifiedHealthData
  class CcdService < UnifiedHealthData::BaseService
    # Initiates CCD generation and returns the job status response.
    # The frontend will poll separately via get_ccd_status with the returned jobId.
    #
    # @return [UnifiedHealthData::Ccd] Parsed initiation response with job metadata
    def initiate_ccd
      validate_icn!
      with_monitoring do
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.generate_ccd(patient_id: @user.icn, start_date:, end_date:)
        ccd = ccd_adapter.parse(response.body)
        ccd.http_status = response.status
        ccd
      end
    end

    # Retrieves status of CCD generation
    # @param job_id [String] The CCD job ID
    # @return [UnifiedHealthData::Ccd] CCD with status of task when processing (202) or of each format (200)
    def get_ccd_status(job_id:)
      with_monitoring do
        response = uhd_client.get_ccd(job_id:)
        ccd = ccd_adapter.parse(response.body)
        ccd.http_status = response.status
        ccd
      end
    end

    # Retrieves presigned url of the specified CCD format
    # @param job_id [String] The CCD job ID
    # @param format [String] The desired format: 'xml', 'pdf', or 'html'
    # @return [String, nil] The presigned URL for the specified format, or nil if not found
    def get_ccd_url(job_id:, format: 'xml')
      with_monitoring do
        response = uhd_client.get_ccd(job_id:)
        body = response.body
        ccd_adapter.parse_url(body, format:)
      end
    end

    # Retrieves a list of available CCD jobs for a user.
    # Each Task entry in the Bundle represents a CCD generation job with artifact metadata.
    #
    # @return [Array<UnifiedHealthData::Ccd>] Array of parsed CCD job objects, or empty array if no tasks found
    def get_ccd_jobs
      validate_icn!
      with_monitoring do
        response = uhd_client.get_ccd_jobs_by_user(patient_id: @user.icn)
        body = response.body

        ccd_adapter.parse_tasks(body)
      end
    end

    private

    def ccd_adapter
      @ccd_adapter ||= UnifiedHealthData::Adapters::CcdAdapter.new
    end
  end
end
