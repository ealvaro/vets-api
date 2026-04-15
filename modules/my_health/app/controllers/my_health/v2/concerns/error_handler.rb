# frozen_string_literal: true

require 'datadog'

module MyHealth
  module V2
    module Concerns
      module ErrorHandler
        extend ActiveSupport::Concern

        private

        # Main error handling orchestrator for UHD V2 endpoints.
        #
        # Handles three exception families:
        #   - Common::Exceptions::GatewayTimeout → 504
        #   - Common::Client::Errors::ClientError → upstream status passed through
        #   - Common::Exceptions::BackendServiceException → upstream status passed through
        #   - Anything else → 500
        #
        # Every path also:
        #   1. Logs the error to Rails.logger
        #   2. Tags the active Datadog span so APM captures the error message and stack trace
        #
        # @param error [Exception] The error to handle
        # @param resource_name [String] The name of the resource (e.g., 'clinical notes', 'vitals')
        # @param api_type [String] The API type ('FHIR', 'SCDF', or 'S3') — used in log messages and error titles
        def handle_error(error, resource_name: nil, api_type: 'FHIR')
          log_error(error, resource_name:, api_type:)
          tag_datadog_span(error)

          case error
          when Common::Exceptions::GatewayTimeout
            render_error('Gateway Timeout', "Upstream #{api_type} service timed out", '504', 504,
                         :gateway_timeout)
          when Common::Client::Errors::ClientError
            handle_client_error(error, api_type)
          when Common::Exceptions::BackendServiceException
            handle_backend_service_error(error, api_type)
          else
            handle_generic_error(resource_name)
          end
        end

        # Logs errors with contextual information
        # @param error [Exception] The error to log
        # @param resource_name [String] The name of the resource
        # @param api_type [String] The API type ('FHIR', 'SCDF', or 'S3')
        def log_error(error, resource_name: nil, api_type: 'FHIR')
          message = case error
                    when Common::Exceptions::GatewayTimeout
                      "#{resource_name} #{api_type} timeout: #{error.message}"
                    when Common::Client::Errors::ClientError
                      "#{resource_name} #{api_type} API error (#{error.status}): #{error.message}"
                    when Common::Exceptions::BackendServiceException
                      "#{resource_name} #{api_type} backend error (#{error.original_status}): " \
                      "#{error.errors.first&.detail}"
                    else
                      "Unexpected error in #{resource_name} controller: #{error.message}"
                    end

          Rails.logger.error(message, backtrace: error.backtrace&.first(10))
        end

        # Tags the active Datadog span so APM captures the error message and stack trace.
        # Also tags the top-level Rack span so errors appear in the Datadog Error Tracking console.
        def tag_datadog_span(error)
          Datadog::Tracing.active_span&.set_error(error)
          request.env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]&.set_error(error)
        end

        # Renders a standardized error response
        # @param title [String] The error title
        # @param detail [String] The error detail message
        # @param code [String] The error code
        # @param status [Integer, String] The status code
        # @param http_status [Symbol] The HTTP status symbol
        def render_error(title, detail, code, status, http_status)
          error = {
            title:,
            detail:,
            code:,
            status:
          }
          render json: { errors: [error] }, status: http_status
        end

        # Maps upstream status to an appropriate vets-api response status.
        #   - 4xx from upstream → pass through (client error or resource not found)
        #   - 5xx from upstream → 502 Bad Gateway (upstream is broken)
        #   - nil/unknown       → 502 Bad Gateway (safe default)
        #
        # @param upstream_status [Integer, nil] The original HTTP status from the upstream service
        # @return [Integer] The mapped HTTP status code
        def map_upstream_status(upstream_status)
          return 502 unless upstream_status.is_a?(Integer) && upstream_status.between?(400, 499)

          upstream_status
        end

        # Handles Common::Client::Errors::ClientError — the upstream status is on error.status
        def handle_client_error(error, api_type)
          status_code = map_upstream_status(error.status)
          render_error("#{api_type} API Error", error.message, status_code.to_s, status_code, status_code)
        end

        # Handles Common::Exceptions::BackendServiceException — the upstream status is on error.original_status
        def handle_backend_service_error(error, api_type)
          status_code = map_upstream_status(error.original_status)
          detail = error.errors.first&.detail || error.message
          render_error("#{api_type} Backend Error", detail, status_code.to_s, status_code, status_code)
        end

        # Handles generic/unexpected errors
        def handle_generic_error(resource_name)
          detail_message = if resource_name
                             "An unexpected error occurred while retrieving #{resource_name}."
                           else
                             'An unexpected error occurred.'
                           end

          render_error('Internal Server Error', detail_message, '500', 500, :internal_server_error)
        end
      end
    end
  end
end
