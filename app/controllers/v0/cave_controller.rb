# frozen_string_literal: true

module V0
  class CaveController < ApplicationController
    service_tag 'cave'

    STATSD_KEY = 'api.cave'

    # The shared CAVE failure contract. bio-cave returns exactly one of these values as the
    # top-level `scan_status` on the doc-status envelope (`status`). vets-api validates the
    # envelope, logs/meters the outcome, and forwards a normalized shape rather than
    # blind-proxying an HTTP-200 body that actually represents a failure.
    #
    # VALID_SCAN_STATUSES points at the single source of truth in Idp so the controller and the
    # Idp::Client metric bucketing can't drift. The named constants below are semantic handles
    # for the case statement in render_cave_envelope.
    SCAN_STATUS_PENDING = 'pending'
    SCAN_STATUS_COMPLETED_WITH_ERRORS = 'completed_with_errors'
    SCAN_STATUS_FAILED = 'failed'
    VALID_SCAN_STATUSES = Idp::SCAN_STATUSES

    before_action :require_cave_feature_enabled
    before_action :log_cave_request, only: %i[create status output download update]
    after_action :log_cave_response, only: %i[create status output download update]

    rescue_from Idp::Error, with: :render_service_error

    def create
      render json: client.intake(
        file_name: intake_params[:file_name],
        pdf_base64: intake_params[:pdf_b64],
        user_id: idp_user_id
      )
    end

    def status
      body = client.status(document_id, user_id: idp_user_id)
      render_cave_envelope(body)
    end

    def output
      type = params[:type].presence || 'artifact'
      body = client.output(document_id, type:, user_id: idp_user_id)

      # `output` returns the extracted `forms` payload, NOT the doc-status envelope, so it has no
      # top-level `scan_status`. Validate the payload shape (a non-empty Hash) rather than the
      # scan_status contract, which only applies to `status`.
      validate_payload_shape!('output', body)
      increment_outcome('output', 'success')
      render json: body
    end

    def download
      kvpid = params.require(:kvpid)

      raw_payload = client.download(document_id, kvpid:, user_id: idp_user_id)

      validate_payload_shape!('download', raw_payload)

      cave_submission = CaveSubmission.new(
        cave_response: raw_payload.to_json,
        cave_document_id: document_id,
        kvpid:,
        idp_user_id:
      )
      cave_submission.save!

      increment_outcome('download', 'success')
      render json: {
        cave_submission_id: cave_submission.id,
        raw_payload:
      }
    end

    def diff
      # Intentionally NOT envelope/payload-shape validated: `diff` is a LOCAL computation
      # (Idp::JsonDiff) over the request's own lhs/rhs, which diff_payload already validates.
      # There is no backend response envelope to guard here.
      payload = diff_payload

      render json: Idp::JsonDiff.new(lhs: payload['lhs'], rhs: payload['rhs']).call
    end

    def update
      kvpid = params.require(:kvpid)
      body = client.update(
        document_id,
        kvpid:,
        payload: update_payload,
        user_id: idp_user_id
      )

      # `update` proxies the backend's replacement KVP payload (no scan_status envelope). It gets
      # the Hash-shape guard, but allows an empty `{}` echo since that is a valid successful
      # mutation (unlike download/output where an empty body is a real failure).
      validate_payload_shape!('update', body, allow_empty: true)
      increment_outcome('update', 'success')
      render json: body
    end

    private

    def intake_params
      params.require(:pdf_b64)
      params.require(:file_name)
      params.permit(:pdf_b64, :file_name)
    end

    def document_id
      params.require(:id)
    end

    def update_payload
      parsed_json_object_body
    end

    def diff_payload
      payload = parsed_json_object_body
      return payload if payload.key?('lhs') && payload.key?('rhs')

      raise Common::Exceptions::BadRequest, detail: "Request body must include 'lhs' and 'rhs'"
    end

    def parsed_json_object_body
      body_text = request.raw_post
      raise ActionController::ParameterMissing, :body if body_text.blank?

      payload = JSON.parse(body_text)
      return payload if payload.is_a?(Hash)

      raise Common::Exceptions::BadRequest, detail: 'Request body must be a JSON object'
    rescue JSON::ParserError
      raise Common::Exceptions::BadRequest, detail: 'Request body must be valid JSON'
    end

    # Validate + normalize the envelope-bearing CAVE doc-status response (the `status` action)
    # before it is forwarded to the website. The backend can return HTTP 200 with a body that
    # represents a failure (`scan_status: failed`) or a partial success
    # (`scan_status: completed_with_errors`); blind-proxying those made silent failures look
    # like successes (they weren't logged/metered and the shape wasn't normalized).
    #
    # ALL four valid statuses return HTTP 200 with the scan_status envelope in the body. The
    # frontend poller treats 5xx as a retryable transport error and only stops on a terminal
    # scanStatus IN a 2xx body, so a `failed` doc must surface as a 200 (with the failure in the
    # body) — raising 502 would make a permanently-failed doc poll until the deadline. We still
    # log + meter the outcome per status. 502 is reserved for genuine transport problems: a
    # missing/unknown scan_status (render_invalid_scan_status) or a malformed non-Hash payload
    # (validate_payload_shape!).
    #   - failed                -> 200 passthrough (failure conveyed in body), metered .failed
    #   - completed_with_errors -> 200 with body + normalized `warnings` array
    #   - pending               -> 200 passthrough, metered .pending
    #   - completed             -> 200 passthrough, metered .success
    #   - missing/unknown       -> 502 Bad Gateway (invalid_scan_status)
    def render_cave_envelope(body)
      scan_status = body.is_a?(Hash) ? body['scan_status'] : nil

      return render_invalid_scan_status(scan_status) unless VALID_SCAN_STATUSES.include?(scan_status)

      log_cave_outcome(scan_status:, body:)

      case scan_status
      when SCAN_STATUS_FAILED
        increment_outcome(action_name, 'failed')
        render json: body
      when SCAN_STATUS_COMPLETED_WITH_ERRORS
        increment_outcome(action_name, 'completed_with_warnings')
        render json: body.merge('warnings' => normalized_warnings(body['warnings']))
      when SCAN_STATUS_PENDING
        increment_outcome(action_name, 'pending')
        render json: body
      else
        increment_outcome(action_name, 'success')
        render json: body
      end
    end

    # Normalizes `warnings` to an Array WITHOUT flattening a structured Hash. Ruby's `Array({...})`
    # would turn a warnings Hash into [[key, value], ...] pairs and corrupt it, so wrap non-Array
    # values in a one-element array instead. Absent/blank warnings become [].
    def normalized_warnings(warnings)
      return [] if warnings.blank?
      return warnings if warnings.is_a?(Array)

      [warnings]
    end

    def render_invalid_scan_status(scan_status)
      increment_outcome(action_name, 'invalid_scan_status')
      Rails.logger.error('[CaveController] invalid CAVE scan_status', {
        request_id: request.request_id,
        action: action_name,
        document_id: params[:id],
        scan_status:
      }.compact)
      raise Common::Exceptions::BadGateway,
            detail: 'Document processing service returned an unrecognized response'
    end

    # Rejects a malformed CAVE payload (download's KVP artifact, output's forms body) before it
    # is used. The payload must be a JSON object; a non-Hash (Array, String, nil) would poison a
    # persisted row or forward a garbage success to the website.
    #
    # allow_empty: download/output require a NON-empty Hash (an empty artifact/forms body is a
    # real failure). `update` passes allow_empty: true because echoing back an empty object `{}`
    # is a legitimate successful mutation (the request parser only requires a JSON object).
    def validate_payload_shape!(action, raw_payload, allow_empty: false)
      return if raw_payload.is_a?(Hash) && (allow_empty || raw_payload.present?)

      increment_outcome(action, 'invalid_payload')
      Rails.logger.error('[CaveController] invalid CAVE payload', {
        request_id: request.request_id,
        action: action_name,
        document_id: params[:id],
        payload_class: raw_payload.class.name
      }.compact)
      raise Common::Exceptions::BadGateway,
            detail: 'Document processing service returned an unrecognized response'
    end

    def log_cave_outcome(scan_status:, body:)
      Rails.logger.info('[CaveController] CAVE outcome', {
        request_id: request.request_id,
        action: action_name,
        document_id: params[:id],
        scan_status:,
        error: body['error'],
        warnings: body['warnings']
      }.compact)
    end

    def increment_outcome(action, outcome)
      StatsD.increment("#{STATSD_KEY}.#{action}.#{outcome}")
    end

    def client
      @client ||= Idp.client
    end

    def idp_user_id
      user_id = current_user&.user_account_uuid.presence || current_user&.uuid
      return user_id if user_id.present?

      raise Common::Exceptions::Forbidden, detail: 'Unable to determine user identity for IDP request'
    end

    def require_cave_feature_enabled
      routing_error unless Flipper.enabled?(:cave_idp)
    end

    def log_cave_request
      @cave_request_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Rails.logger.info('[CaveController] incoming request', {
                          request_id: request.request_id,
                          action: action_name,
                          document_id: params[:id],
                          endpoint: request.env['action_dispatch.route_uri_pattern'],
                          method: request.method
                        })
    end

    def log_cave_response
      duration_ms = if @cave_request_start
                      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @cave_request_start) * 1000).round(2)
                    end

      Rails.logger.info('[CaveController] request complete', {
        request_id: request.request_id,
        action: action_name,
        document_id: params[:id],
        status: response.status,
        success: response.successful?,
        duration_ms:
      }.compact)
    end

    def render_service_error(error)
      mapped_status = map_error_status(error)
      status_code = mapped_status_code(mapped_status)
      error_code = map_error_code(error, mapped_status)
      detail = public_error_detail(error, mapped_status)
      active_span = Datadog::Tracing.active_span
      rack_span = request.env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]

      mark_error_spans(active_span:, rack_span:, error:, status_code:, error_code:)
      log_upstream_request_failure(error:, status_code:, error_code:)
      report_service_error_to_sentry(error:, status_code:, error_code:)

      render json: {
        errors: [
          {
            title: error_title(status_code),
            code: error_code,
            status: status_code.to_s,
            detail:
          }
        ]
      }, status: mapped_status
    end

    def map_error_status(error)
      case error.upstream_status_code
      when 400
        error.operation == 'intake' ? :bad_request : :bad_gateway
      when 403
        :forbidden
      when 404
        :not_found
      when 415
        :unsupported_media_type
      when 422
        :unprocessable_entity
      else
        :bad_gateway
      end
    end

    def map_error_code(error, mapped_status)
      return 'idp_transport_error' if error.transport_failure?

      case mapped_status.to_sym
      when :bad_request
        'idp_bad_request'
      when :forbidden
        'idp_forbidden'
      when :not_found
        'idp_not_found'
      when :unsupported_media_type
        'idp_unsupported_media_type'
      when :unprocessable_entity
        'idp_unprocessable_entity'
      else
        error.upstream_status_code == 401 ? 'idp_upstream_auth_error' : 'idp_upstream_unavailable'
      end
    end

    def public_error_detail(error, mapped_status)
      upstream_detail = extract_upstream_detail(error.upstream_body)

      case mapped_status.to_sym
      when :forbidden, :not_found, :unsupported_media_type, :unprocessable_entity
        upstream_detail.presence || default_error_detail(mapped_status)
      when :bad_request
        if error.operation == 'intake'
          upstream_detail.presence || default_error_detail(mapped_status)
        else
          'Document processing request could not be completed'
        end
      else
        default_error_detail(mapped_status)
      end
    end

    def default_error_detail(mapped_status)
      return 'Document processing request could not be completed' if mapped_status.to_sym == :bad_request

      'Document processing service is temporarily unavailable'
    end

    def extract_upstream_detail(body)
      case body
      when Hash
        body.dig('errors', 0, 'detail') ||
          body.dig('errors', 0, 'title') ||
          body['error_message'] ||
          body['error']
      when String
        body
      end&.to_s&.strip&.presence
    end

    def tag_error_span(span, error, status_code:, error_code:)
      return unless span

      span.set_tag('cave.operation', error.operation) if error.operation.present?
      span.set_tag('cave.error_type', error.error_type) if error.error_type.present?
      span.set_tag('cave.error_code', error_code)
      span.set_tag('cave.upstream_status', error.upstream_status_code) if error.upstream_status_code.present?
      span.set_tag('cave.mapped_status', status_code)
    end

    def mark_error_spans(active_span:, rack_span:, error:, status_code:, error_code:)
      active_span&.set_error(error)
      rack_span&.set_error(error) unless rack_span == active_span
      tag_error_span(active_span, error, status_code:, error_code:)
      tag_error_span(rack_span, error, status_code:, error_code:) unless rack_span == active_span
    end

    def log_upstream_request_failure(error:, status_code:, error_code:)
      Rails.logger.warn('[CaveController] upstream request failed', {
        request_id: request.request_id,
        action: action_name,
        document_id: params[:id],
        operation: error.operation,
        error_type: error.error_type,
        upstream_status: error.upstream_status_code,
        mapped_status: status_code,
        error_code:
      }.compact)
    end

    def report_service_error_to_sentry(error:, status_code:, error_code:)
      Rails.logger.error(error.message, {
        cave_document_id: params[:id],
        cave_endpoint: request.path,
        cave_request_id: request.request_id,
        cave_upstream_status: error.upstream_status_code,
        cave_mapped_status: status_code
      }.compact.merge({
        error_type: error.error_type,
        operation: error.operation,
        error_code:
      }.compact))
    end

    def error_title(status_code)
      Rack::Utils::HTTP_STATUS_CODES.fetch(status_code, 'Error')
    end

    def mapped_status_code(mapped_status)
      Rack::Utils.status_code(mapped_status)
    end
  end
end
