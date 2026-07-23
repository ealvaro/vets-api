# frozen_string_literal: true

require 'digital_forms_api/service/submissions'
require 'digital_forms_api/service/templates'
require 'digital_forms_api/monitor'

module DigitalFormsApi
  # The Fully Digital Forms controller that handles fetching form submissions and templates
  class SubmissionsController < ApplicationController
    service_tag 'digital-forms'
    # The FORM_ID constant for the 21-686c
    FORM_ID = '21-686c'

    before_action :check_flipper_flag

    # Fetch form submission and template from Forms API
    # Endpoint: GET /digital_forms_api/submissions/:id
    # Response: 200 with submission and template details, or appropriate error status
    def show
      started_at = monotonic_now
      stage = :retrieve_submission

      submission = SubmissionResponse.new(submissions_service.retrieve(params[:id], form_id: FORM_ID))
      stage = :authorize_submission
      return unless authorize_submission_access!(submission, started_at:)

      stage = :fetch_template
      template_details, template_version = fetch_template_details
      track_success(template_version, started_at:)

      stage = :render_submission
      render_submission(submission, template_details)
    rescue Common::Client::Errors::ClientError => e
      handle_client_error(e, failure_stage: stage.to_s, started_at:)
    rescue => e
      handle_unexpected_error(e, failure_stage: stage.to_s, started_at:)
    end

    private

    # Authorize that the current user is able to access the submission
    # Auth is based on whether the veteranId in the submission matches current_user
    # If unauthorized, log the attempt and return a 403 response
    # @param submission [DigitalFormsApi::SubmissionResponse] the wrapped submission-retrieval response
    # @return [Boolean] true if authorized, false if not (after rendering the forbidden response)
    def authorize_submission_access!(submission, started_at:)
      veteran_id = submission.veteran_id
      denial_reason = denial_reason_for_veteran_id(veteran_id)
      return true unless denial_reason

      # using Rails.logger.warn here to ensure the log is emitted even if
      # StatsD is unavailable for some reason
      # Since this is a potential security concern (auth)
      # We want to ensure we have logs of these events regardless of StatsD availability
      Rails.logger.warn(
        'Digital Forms API - Veteran participant ID is forbidden to access this submission',
        form_id: FORM_ID,
        submission_id: params[:id],
        veteran_identifier_type: veteran_id.is_a?(Hash) ? veteran_id['identifierType'] : nil,
        user_participant_id_present: current_user&.participant_id.present?
      )
      track_show(
        http_status: 403,
        failure_stage: 'authorize_submission',
        auth_denial_reason: denial_reason,
        duration_ms: elapsed_ms(started_at)
      )
      render json: { error: 'Forbidden' }, status: :forbidden
      false
    end

    # Fetch the form template details and version from the Forms API
    # @return [Array<Hash, String>] the template details hash and the template version string
    def fetch_template_details
      template = templates_service.template(FORM_ID)
      template_details = template.fetch('formTemplate').fetch('formTemplate').fetch(FORM_ID)
      template_version = template_details&.[]('version')
      [template_details, template_version]
    end

    # Track a successful retrieval of the submission and template details
    # @param template_version [String] the version of the template that was retrieved
    def track_success(template_version, started_at:)
      monitor.track_template_version(form_id: FORM_ID, template_version:)
      track_show(
        http_status: 200,
        template_version:,
        failure_stage: 'none',
        duration_ms: elapsed_ms(started_at)
      )
    end

    # Render the submission and template details in the response
    # @param submission [DigitalFormsApi::SubmissionResponse] the wrapped submission-retrieval response
    # @param template_details [Hash] the details of the form template that was retrieved
    def render_submission(submission, template_details)
      render json: {
        submission: submission.payload,
        template: template_details
      }
    end

    # Handle client errors from the service calls, such as 404 not found or other client errors
    # Log the error and return an appropriate JSON response with the error message and status code
    # @param error [Common::Client::Errors::ClientError] the error object raised by the service client
    def handle_client_error(error, failure_stage:, started_at:)
      status = error.status == 404 ? 404 : 500
      track_show(
        http_status: status,
        failure_stage:,
        error_source: 'client_error',
        duration_ms: elapsed_ms(started_at),
        **error_context(error)
      )
      if status == 404
        render json: { error: 'Not found' }, status: :not_found
      else
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end
    end

    # Handle unexpected errors that are not client errors
    # Log the error and return a 500 JSON response
    # @param error [StandardError] the error object raised by the controller action
    def handle_unexpected_error(error, failure_stage:, started_at:)
      track_show(
        http_status: 500,
        failure_stage:,
        error_source: 'unexpected_error',
        duration_ms: elapsed_ms(started_at),
        **error_context(error, include_upstream: false)
      )
      raise
    end

    # Check the Flipper flag to determine if the endpoint should be accessible
    # If the flag is disabled, raise a Forbidden error to prevent access
    # @raise [Common::Exceptions::Forbidden] if the Flipper flag is disabled for the current user
    def check_flipper_flag
      return if Flipper.enabled?(:dependents_digital_forms_api_submission_enabled, current_user)

      track_show(
        http_status: 403,
        failure_stage: 'feature_flag',
        auth_denial_reason: 'feature_flag_disabled',
        feature_flag_enabled: false
      )
      raise Common::Exceptions::Forbidden
    end

    # Instantiate service for interacting with the /forms endpoints
    # @return [DigitalFormsApi::Service::Templates] the templates service instance
    def templates_service
      DigitalFormsApi::Service::Templates.new
    end

    # Instantiate service for interacting with the /submissions endpoints
    # @return [DigitalFormsApi::Service::Submissions] the submissions service instance
    def submissions_service
      DigitalFormsApi::Service::Submissions.new
    end

    # Instantiate the monitor for tracking events in this controller
    # @return [DigitalFormsApi::Monitor::Controller] the monitor instance for this controller
    def monitor
      @monitor ||= DigitalFormsApi::Monitor::Controller.new
    end

    # Track the show event with the given HTTP status and context information
    # @param http_status [Integer] the HTTP status code to track for this event
    # @param context [Hash] additional context information to include in the tracking event, such
    #  as template_version, error details, and upstream response details
    def track_show(http_status:, **context)
      monitor.track_show(
        http_status:,
        submission_id: params[:id],
        form_id: FORM_ID,
        **context
      )
    end

    # Format the error context for tracking, including error class and message
    # @param error [StandardError] the error object to extract context from
    # @param include_upstream [Boolean] whether to include upstream status and reason
    # @return [Hash] a hash of error context information to include in tracking events
    def error_context(error, include_upstream: true)
      context = { error_class: error.class.to_s, error: error.message }
      return context unless include_upstream && error.respond_to?(:status)

      upstream_reason = error.try(:body).is_a?(Hash) ? (error.body['message'] || error.message) : error.message
      context.merge(upstream_status: error.status, upstream_reason:)
    end

    # Get the current monotonic time for measuring durations
    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Calculate the elapsed time in milliseconds since the given start time
    def elapsed_ms(started_at)
      ((monotonic_now - started_at) * 1000).round
    end

    # Determine the denial reason for a given veteran ID
    # based on the current user's participant ID and the structure of the veteran ID
    # @return [String, nil] the denial reason if the veteran ID is not authorized, or nil if authorized
    def denial_reason_for_veteran_id(veteran_id)
      return 'missing_participant_id' if current_user&.participant_id.blank?
      return 'malformed_veteran_id' unless veteran_id.is_a?(Hash)
      return 'identifier_type_mismatch' unless veteran_id['identifierType'] == 'PARTICIPANTID'
      return 'participant_id_mismatch' unless veteran_id['value'] == current_user.participant_id

      nil
    end
  end
end
