# frozen_string_literal: true

require 'digital_forms_api/dpdf_downloader'
require 'digital_forms_api/monitor'

module DigitalFormsApi
  # Serves a veteran's filed dPDF (686/674) for the my-VA viewing path by reading it back from
  # Claims Evidence. This repurposes the former Forms API read-back endpoint: same route and same
  # feature flag, but the response is now the PDF document itself, sourced directly from Claims
  # Evidence (not the Forms API, and not the FormRenderer viewer MFE).
  class SubmissionsController < ApplicationController
    service_tag 'digital-forms'

    # STI types of the dependents child claims (21-686c / 21-674) whose filed dPDF this endpoint serves.
    # Scoping the lookup to these keeps the query off unrelated claims (and off the dependents parent).
    DPDF_CLAIM_TYPES = %w[
      DependentsBenefits::AddRemoveDependent
      DependentsBenefits::SchoolAttendanceApproval
    ].freeze

    before_action :check_flipper_flag

    # Stream the veteran's filed dPDF for the given child-claim guid, read from Claims Evidence.
    # Endpoint: GET /digital_forms_api/submissions/:id  (:id is the child SavedClaim guid)
    # Response: 200 application/pdf, or 403 (not the owner) / 404 (no matching claim, or nothing filed yet) / 500.
    def show
      started_at = monotonic_now
      claim = SavedClaim.where(type: DPDF_CLAIM_TYPES).find_by(guid: params[:id])
      return render_not_found(started_at:) if claim.nil?
      return render_forbidden(claim, started_at:) unless owned_by_current_user?(claim)

      pdf = DpdfDownloader.new(claim).fetch
      track_show(http_status: 200, form_id: claim.form_id, failure_stage: 'none', duration_ms: elapsed_ms(started_at))
      send_data pdf, type: 'application/pdf', disposition: 'inline', filename: "#{claim.form_id}.pdf"
    rescue DpdfDownloader::NotFiled => e
      render_not_found(started_at:, claim:, error: e)
    rescue Common::Client::Errors::ClientError => e
      handle_client_error(e, claim:, started_at:)
    rescue Common::Exceptions::GatewayTimeout => e
      track_upstream_failure(e, claim:, started_at:, http_status: 504)
    rescue Breakers::OutageException => e
      track_upstream_failure(e, claim:, started_at:, http_status: 503)
    rescue => e
      handle_unexpected_error(e, claim:, started_at:)
    end

    private

    # Authorize that the current user owns this claim. Ownership is the claim's user_account matching
    # the authenticated user's; fail closed when either side is missing.
    # @param claim [SavedClaim] the claim being requested
    # @return [Boolean] true only if the current user owns the claim
    def owned_by_current_user?(claim)
      account_id = current_user&.user_account&.id
      account_id.present? && claim.user_account_id.present? && claim.user_account_id == account_id
    end

    # Render a 404, tracking the event. Used for an unknown guid or a claim with nothing filed yet.
    def render_not_found(started_at:, claim: nil, error: nil)
      context = error ? error_context(error, include_upstream: false) : {}
      track_show(http_status: 404, form_id: claim&.form_id, failure_stage: 'retrieve_submission',
                 duration_ms: elapsed_ms(started_at), **context)
      render json: { error: 'Not found' }, status: :not_found
    end

    # Render a 403, logging the denied access (auth is a security concern, so log regardless of StatsD).
    def render_forbidden(claim, started_at:)
      Rails.logger.warn(
        'Digital Forms API - user is forbidden to access this submission',
        form_id: claim.form_id, submission_id: params[:id]
      )
      track_show(http_status: 403, form_id: claim.form_id, failure_stage: 'authorize_submission',
                 auth_denial_reason: 'not_owner', duration_ms: elapsed_ms(started_at))
      render json: { error: 'Forbidden' }, status: :forbidden
    end

    # Handle a Claims Evidence client error: 404 passes through as not-found, everything else is a 500.
    def handle_client_error(error, claim:, started_at:)
      status = error.status == 404 ? 404 : 500
      track_show(http_status: status, form_id: claim&.form_id, failure_stage: 'download_dpdf',
                 error_source: 'client_error', duration_ms: elapsed_ms(started_at), **error_context(error))
      if status == 404
        render json: { error: 'Not found' }, status: :not_found
      else
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end
    end

    # Track an expected upstream failure (Claims Evidence timeout or an open circuit breaker) with the
    # status the framework will render, then re-raise so the default handling produces that response —
    # keeps the emitted metric/log status in step with what the veteran actually receives.
    def track_upstream_failure(error, claim:, started_at:, http_status:)
      track_show(http_status:, form_id: claim&.form_id, failure_stage: 'download_dpdf',
                 error_source: 'upstream_unavailable', duration_ms: elapsed_ms(started_at),
                 **error_context(error, include_upstream: false))
      raise error
    end

    # Handle an unexpected error: track a 500 and re-raise for the default error handling.
    def handle_unexpected_error(error, claim:, started_at:)
      track_show(http_status: 500, form_id: claim&.form_id, failure_stage: 'download_dpdf',
                 error_source: 'unexpected_error', duration_ms: elapsed_ms(started_at),
                 **error_context(error, include_upstream: false))
      raise
    end

    # Gate the endpoint on the Flipper flag; a disabled flag returns 403 Forbidden.
    def check_flipper_flag
      return if Flipper.enabled?(:dependents_digital_forms_api_submission_enabled, current_user)

      track_show(http_status: 403, failure_stage: 'feature_flag', auth_denial_reason: 'feature_flag_disabled',
                 feature_flag_enabled: false)
      raise Common::Exceptions::Forbidden
    end

    # @return [DigitalFormsApi::Monitor::Controller] the monitor for this controller
    def monitor
      @monitor ||= DigitalFormsApi::Monitor::Controller.new
    end

    # Track a submissions#show event, always supplying the submission id from params.
    def track_show(http_status:, form_id: nil, **context)
      form_id = form_id.to_s.downcase.presence
      monitor.track_show(http_status:, submission_id: params[:id], form_id:, **context)
    end

    # Format the error context for tracking, including error class and message.
    # @param error [StandardError] the error to extract context from
    # @param include_upstream [Boolean] whether to include upstream status and reason
    # @return [Hash] the error context
    def error_context(error, include_upstream: true)
      context = { error_class: error.class.to_s, error: error.message }
      return context unless include_upstream && error.respond_to?(:status)

      upstream_reason = error.try(:body).is_a?(Hash) ? (error.body['message'] || error.message) : error.message
      context.merge(upstream_status: error.status, upstream_reason:)
    end

    # @return [Float] the current monotonic time, for measuring durations
    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # @param started_at [Float] a monotonic start time
    # @return [Integer] elapsed milliseconds since started_at
    def elapsed_ms(started_at)
      ((monotonic_now - started_at) * 1000).round
    end
  end
end
