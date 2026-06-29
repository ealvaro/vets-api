# frozen_string_literal: true

module V0
  class CaveController < ApplicationController
    service_tag 'cave'

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
      render json: client.status(document_id, user_id: idp_user_id)
    end

    def output
      type = params[:type].presence || 'artifact'
      render json: client.output(document_id, type:, user_id: idp_user_id)
    end

    def download
      kvpid = params.require(:kvpid)

      raw_payload = client.download(document_id, kvpid:, user_id: idp_user_id)

      cave_submission = CaveSubmission.new(
        cave_response: raw_payload.to_json,
        cave_document_id: document_id,
        kvpid:,
        idp_user_id:
      )
      cave_submission.save!

      render json: {
        cave_submission_id: cave_submission.id,
        raw_payload:
      }
    end

    def diff
      payload = diff_payload

      render json: Idp::JsonDiff.new(lhs: payload['lhs'], rhs: payload['rhs']).call
    end

    def update
      kvpid = params.require(:kvpid)
      render json: client.update(
        document_id,
        kvpid:,
        payload: update_payload,
        user_id: idp_user_id
      )
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
