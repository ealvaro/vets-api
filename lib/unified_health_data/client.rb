# frozen_string_literal: true

require 'common/client/base'
require 'common/exceptions/upstream_partial_failure'
require_relative 'configuration'
require_relative 'operation_outcome_detector'
require_relative 'constants'

module UnifiedHealthData
  class Client < Common::Client::Base
    include Constants
    include Common::Client::Concerns::Monitoring

    configuration UnifiedHealthData::Configuration

    def get_allergies_by_date(patient_id:, start_date:, end_date:, no_cache: false)
      path = "#{config.base_path}allergies?patientId=#{patient_id}&startDate=#{start_date}&endDate=#{end_date}"
      perform(:get, path, nil, request_headers(no_cache:))
    end

    def get_labs_by_date(patient_id:, start_date:, end_date:, no_cache: false)
      path = "#{config.base_path}labs?patientId=#{patient_id}&startDate=#{start_date}&endDate=#{end_date}"
      perform(:get, path, nil, request_headers(no_cache:))
    end

    def get_conditions_by_date(patient_id:, start_date:, end_date:, no_cache: false)
      path = "#{config.base_path}conditions?patientId=#{patient_id}&startDate=#{start_date}&endDate=#{end_date}"
      perform(:get, path, nil, request_headers(no_cache:))
    end

    def get_notes_by_date(patient_id:, start_date:, end_date:, no_cache: false)
      path = "#{config.base_path}notes?" \
             "patientId=#{patient_id}&startDate=#{start_date}" \
             "&endDate=#{end_date}&includeBinary=false"
      perform(:get, path, nil, request_headers(no_cache:))
    end

    def get_note_by_source(patient_id:, source:, record_id:, start_date:, end_date:)
      encoded_source = ERB::Util.url_encode(source)
      encoded_record_id = ERB::Util.url_encode(record_id)
      path = "#{config.base_path}notes/#{encoded_source}/#{encoded_record_id}"
      params = { patientId: patient_id, startDate: start_date, endDate: end_date }
      perform(:get, path, params, request_headers)
    end

    def get_vitals_by_date(patient_id:, start_date:, end_date:, no_cache: false)
      path = "#{config.base_path}vitals?patientId=#{patient_id}&startDate=#{start_date}&endDate=#{end_date}"
      perform(:get, path, nil, request_headers(no_cache:))
    end

    def get_immunizations_by_date(patient_id:, start_date:, end_date:, no_cache: false)
      path = "#{config.base_path}immunizations?patientId=#{patient_id}&startDate=#{start_date}&endDate=#{end_date}"
      perform(:get, path, nil, request_headers(no_cache:))
    end

    def get_prescriptions_by_date(patient_id:, start_date:, end_date:)
      path = "#{config.base_path}medications?patientId=#{patient_id}&startDate=#{start_date}&endDate=#{end_date}"
      perform(:get, path, nil, request_headers)
    end

    def refill_prescription_orders(request_body)
      path = "#{config.base_path}medications/rx/refill"
      perform(:post, path, request_body.to_json, request_headers(include_content_type: true))
    end

    def get_by_docref(doc_id:, include_binary: true)
      path = "#{config.base_path}document-reference/oracle-health/#{doc_id}?includeBinary=#{include_binary}"
      perform(:get, path, nil, request_headers)
    end

    # use of this is behind va_online_scheduling_uhd_avs_metadata
    def get_all_avs(patient_id:, start_date:, end_date:)
      path = "#{config.base_path}avs/oracle-health"
      params = { patientId: patient_id, startDate: start_date, endDate: end_date }
      perform(:get, path, params, request_headers)
    end

    def generate_ccd(patient_id:, start_date:, end_date:)
      path = "#{config.base_path}ccd/#{SourceConstants::ORACLE_HEALTH}"
      params = { patientId: patient_id, startDate: start_date, endDate: end_date }
      perform(:get, path, params, request_headers)
    end

    def get_ccd(job_id:)
      path = "#{config.base_path}ccd/#{SourceConstants::ORACLE_HEALTH}/jobs/#{job_id}"
      perform(:get, path, nil, request_headers)
    end

    def get_ccd_jobs_by_user(patient_id:)
      path = "#{config.base_path}ccd/#{SourceConstants::ORACLE_HEALTH}/jobs?patientId=#{patient_id}"
      perform(:get, path, nil, request_headers)
    end

    def get_imaging_studies(patient_id:, start_date:, end_date:, no_cache: false, **options)
      imaging_study_type = options.fetch(:imaging_study_type, 'RADIOLOGY')
      site_ids = options.fetch(:site_ids, [])
      path = "#{config.base_path}imaging-studies?patientId=#{patient_id}&startDate=#{start_date}&endDate=#{end_date}"
      body = { siteIds: site_ids }
      body[:imagingStudyType] = imaging_study_type
      perform(:post, path, body.to_json, request_headers(include_content_type: true, no_cache:))
    end

    def get_imaging_study(patient_id:, start_date:, end_date:, record_id:)
      path = "#{config.base_path}imaging-study"
      params = { patientId: patient_id, startDate: start_date, endDate: end_date, recordId: record_id }
      perform(:get, path, params, request_headers)
    end

    def get_dicom_zip(patient_id:, start_date:, end_date:, record_id:)
      path = "#{config.base_path}dicom-zip"
      params = { patientId: patient_id, startDate: start_date, endDate: end_date, recordId: record_id }
      perform(:get, path, params, request_headers)
    end

    private

    # Override perform to detect OperationOutcome issues in FHIR responses.
    # Error-level OperationOutcomes raise exceptions (existing behavior).
    # Warning-level OperationOutcomes are attached to the response body as '_warnings'
    # so downstream services/controllers can surface them to the frontend.
    #
    # @param method [Symbol] HTTP method (:get, :post, etc.)
    # @param path [String] API path
    # @param params [Hash, nil] Request parameters or body
    # @param headers [Hash, nil] Request headers
    # @return [Faraday::Response] The response from the API
    # @raise [Common::Exceptions::UpstreamPartialFailure] when error-level OperationOutcomes detected
    def perform(method, path, params = nil, headers = nil)
      response = super
      check_for_operation_outcomes!(response, path)
      response
    end

    # Scans the response for OperationOutcome resources.
    # Errors raise immediately. Warnings are injected into the response body for downstream use.
    #
    # @param response [Faraday::Response] The response from the API
    # @param path [String] The API path for logging/metrics
    # @raise [Common::Exceptions::UpstreamPartialFailure] when error-level OperationOutcomes detected
    def check_for_operation_outcomes!(response, path)
      detector = OperationOutcomeDetector.new(response.body)
      resource_type = extract_resource_type(path)

      if detector.partial_failure?
        detector.log_and_track(resource_type:)
        handle_partial_failure!(detector, response)
      elsif detector.warnings? && response.body.is_a?(Hash)
        detector.log_and_track_warnings(resource_type:)
        response.body['_warnings'] = detector.warning_details
      end
    end

    # Handles partial failure detection: either injects warnings for recoverable
    # single-source failures or raises UpstreamPartialFailure.
    #
    # NOTE: If errors and warnings co-exist (e.g., VistA times out but Oracle Health has a
    # missing Binary warning), the error takes precedence and warnings are not surfaced.
    # This is intentional — a source-level failure already triggers UpstreamPartialFailure
    # handling, and the warning about a missing attachment is secondary.
    def handle_partial_failure!(detector, response)
      if Flipper.enabled?(:mhv_medical_records_partial_failure_handling) &&
         detector.recoverable_failure? && !detector.all_sources_failed?
        # Recoverable single-source failure: inject failure details as warnings
        # so downstream services/controllers render partial data with 206
        response.body['_warnings'] = detector.failure_details if response.body.is_a?(Hash)
      else
        raise Common::Exceptions::UpstreamPartialFailure.new(
          failed_sources: detector.failed_sources,
          failure_details: detector.failure_details
        )
      end
    end

    # Extracts the resource type from the API path for logging and metrics
    # @param path [String] The API path (e.g., "/uhd/v1/allergies?patientId=...")
    # @return [String] The resource type (e.g., "allergies")
    def extract_resource_type(path)
      # Extract resource type from path like "/uhd/v1/allergies?..." or "/uhd/v1/ccd/oracle-health"
      path_without_query = path.split('?').first
      segments = path_without_query.split('/')
      # Find the segment after the version (e.g., "v1")
      version_index = segments.index { |s| s.match?(/^v\d+$/) }
      return 'unknown' unless version_index

      segments[version_index + 1] || 'unknown'
    end

    def fetch_access_token
      with_monitoring do
        response = connection.post(config.token_path) do |req|
          req.headers['Content-Type'] = 'application/json'
          req.headers['x-api-key'] = config.x_api_key if Flipper.enabled?(:mhv_uhd_api_gateway_security_endpoint)
          req.body = {
            appId: config.app_id,
            appToken: config.app_token,
            subject: config.subject,
            userType: config.user_type
          }.to_json
        end
        if Flipper.enabled?(:mhv_uhd_api_gateway_security_endpoint)
          # The AWS API Gateway remaps the login response's `Authorization` header to
          # `x-amzn-remapped-authorization`. When the security endpoint is reached
          # directly (e.g. via the fwdproxy NLB backend, bypassing the gateway) it
          # returns the standard `authorization` header instead, so fall back to it.
          response.headers['x-amzn-remapped-authorization'] || response.headers['authorization']
        else
          response.headers['authorization']
        end
      end
    end

    def request_headers(include_content_type: false, no_cache: false)
      request_id = RequestStore.store['request_id']
      unless request_id
        request_id = SecureRandom.uuid
        Rails.logger.info('UHD Client: Generated fallback X-Request-Id for non-HTTP context', request_id:)
      end
      headers = {
        'Authorization' => fetch_access_token,
        'x-api-key' => config.x_api_key,
        'X-Request-Id' => request_id,
        'x-mhv-client-application' => client_application
      }
      headers['Cache-Control'] = 'no-cache' if ActiveModel::Type::Boolean.new.cast(no_cache)
      headers['Content-Type'] = 'application/json' if include_content_type
      headers
    end

    # Resolves the client application identifier for the x-mhv-client-application header.
    # Reads the source set by SourceAppMiddleware (controllers) or
    # SidekiqStatsInstrumentation::ServerMiddleware (background jobs) in RequestStore.
    # If a Sidekiq job propagates 'va-health-benefits-app' from an originating mobile
    # request, attributing that job to VAHB is intentional.
    def client_application
      source = RequestStore.store.dig('additional_request_attributes', 'source')
      source == 'va-health-benefits-app' ? CLIENT_APPLICATION_VAHB : CLIENT_APPLICATION_VAGOV
    end
  end
end
