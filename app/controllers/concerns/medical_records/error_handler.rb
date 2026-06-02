# frozen_string_literal: true

require 'datadog'
require 'openssl'

module MedicalRecords
  ##
  # Shared error-handling concern for Medical Records controllers.
  #
  # Provides structured JSON error envelopes, Datadog span tagging, and
  # Logging::Monitor metric tracking for upstream failures.
  #
  # == Monitor prefix
  #
  # By default the Logging::Monitor is created with the prefix
  # +'mhv-medical-records'+.  Including controllers can override this by
  # redefining the private method:
  #
  #   class MyController < ApplicationController
  #     include MedicalRecords::ErrorHandler
  #
  #     private
  #
  #     def error_handler_monitor_prefix
  #       'mobile-medical-records'
  #     end
  #   end
  #
  module ErrorHandler
    extend ActiveSupport::Concern

    private

    # Main error handling orchestrator
    # @param error [Exception] The error to handle
    # @param resource_name [String] The name of the resource (e.g., 'clinical notes', 'vitals')
    # @param api_type [String] The API type ('FHIR' or 'SCDF')
    # @param use_dynamic_status [Boolean] Whether to use dynamic HTTP status based on error status (default: false)
    # @param include_backtrace [Boolean] Whether to include backtrace in logs (default: false)
    def handle_error(error, resource_name: nil, api_type: 'FHIR', use_dynamic_status: false,
                     include_backtrace: false)
      log_error(error, resource_name:, api_type:, include_backtrace:)
      tag_datadog_span(error)

      case error
      when Common::Exceptions::NotImplemented
        # Re-raise to let the global exception handler render a 501.
        raise error
      when Common::Exceptions::GatewayTimeout, Timeout::Error
        handle_timeout_error(error)
      when Common::Client::Errors::ClientError
        handle_client_error(error, api_type, use_dynamic_status:)
      when Common::Exceptions::BackendServiceException
        handle_backend_service_error(error, api_type)
      when Common::Exceptions::UpstreamPartialFailure
        detail = error.errors.first&.detail || error.message
        render_error("#{api_type} Upstream Partial Failure", detail, '502', 502, :bad_gateway)
      when Breakers::OutageException, SocketError, OpenSSL::SSL::SSLError
        render_error('Service Unavailable', 'Upstream service unavailable', '503', 503, :service_unavailable)
      else
        handle_generic_error(resource_name)
      end
    end

    # Logs errors with contextual information
    # @param error [Exception] The error to log
    # @param resource_name [String] The name of the resource
    # @param api_type [String] The API type ('FHIR' or 'SCDF')
    # @param include_backtrace [Boolean] Whether to include backtrace in logs
    def log_error(error, resource_name: nil, api_type: 'FHIR', include_backtrace: false)
      message, metric = error_log_attributes(error, resource_name, api_type)
      normalized_resource = resource_name&.parameterize(separator: '_')
      tags = ["error_class:#{error.class.name}", "resource:#{normalized_resource}"]

      monitor.track_request(:error, message, metric, error_class: error.class.name, resource_name:, tags:)

      return unless include_backtrace && error.backtrace

      monitor.track_request(:error, "Backtrace: #{error.backtrace.first(10).join("\n")}",
                            "#{metric_namespace}.error_backtrace", resource_name:, tags:)
    end

    def error_log_attributes(error, resource_name, api_type)
      msg = error.message
      ns = metric_namespace

      case error
      when Common::Exceptions::NotImplemented
        ["#{resource_name} #{api_type} not implemented: #{msg}", "#{ns}.not_implemented"]
      when Common::Exceptions::GatewayTimeout, Timeout::Error
        ["#{resource_name} #{api_type} upstream timeout: #{msg}", "#{ns}.client_error"]
      when Common::Client::Errors::ClientError
        ["#{resource_name} #{api_type} API error: #{msg}", "#{ns}.client_error"]
      when Common::Exceptions::BackendServiceException
        ["Backend service exception: #{error.errors.first&.detail}", "#{ns}.backend_service_error"]
      when Common::Exceptions::UpstreamPartialFailure
        ["#{resource_name} #{api_type} upstream partial failure: #{msg}",
         "#{ns}.upstream_partial_failure"]
      when Breakers::OutageException, SocketError, OpenSSL::SSL::SSLError
        ["#{resource_name} #{api_type} service unavailable: #{msg}", "#{ns}.service_unavailable"]
      else
        ["Unexpected error in #{resource_name} controller: #{msg}", "#{ns}.unexpected_error"]
      end
    end

    # Renders a standardized error response
    # @param title [String] The error title
    # @param detail [String] The error detail message
    # @param code [String] The error code
    # @param status [Integer, String] The status code
    # @param http_status [Symbol] The HTTP status symbol
    def render_error(title, detail, code, status, http_status)
      render json: { errors: [{ title:, detail:, code:, status: }] }, status: http_status
    end

    # Maps an upstream HTTP status to the appropriate vets-api response status.
    # 4xx → pass through, everything else → 502.
    def upstream_status_or_bad_gateway(status)
      (code = status.to_i).between?(400, 499) ? code : 502
    end

    def integer_status_to_symbol(status)
      Rack::Utils::SYMBOL_TO_STATUS_CODE.key(status) || :bad_gateway
    end

    def handle_client_error(error, api_type = 'FHIR', use_dynamic_status: false)
      if error.status.nil? || error.status.to_i.zero?
        render_error("#{api_type} API Error", error.message, '503', 503, :service_unavailable)
      else
        status = use_dynamic_status ? upstream_status_or_bad_gateway(error.status) : 502
        render_error("#{api_type} API Error", error.message, status.to_s, status, integer_status_to_symbol(status))
      end
    end

    def handle_timeout_error(error)
      return render json: { errors: error.errors }, status: :gateway_timeout if error.respond_to?(:errors)

      render_error('Gateway Timeout', 'Upstream service timed out', '504', 504, :gateway_timeout)
    end

    def handle_backend_service_error(error, api_type)
      status = upstream_status_or_bad_gateway(error.original_status)
      detail = error.errors.first&.detail || error.message
      render_error("#{api_type} Backend Error", detail, status.to_s, status, integer_status_to_symbol(status))
    end

    # Tags the active Datadog span and Rack span so errors appear in APM and Error Tracking.
    def tag_datadog_span(error)
      Datadog::Tracing.active_span&.set_error(error)
      request.env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]&.set_error(error)
    end

    # Handles generic/unexpected errors
    def handle_generic_error(resource_name)
      base = 'An unexpected error occurred'
      detail = resource_name ? "#{base} while retrieving #{resource_name}." : "#{base}."
      render_error('Internal Server Error', detail, '500', 500, :internal_server_error)
    end

    # Returns the monitor prefix used for Logging::Monitor.
    # Override in including controllers to customise the service tag and log payload.
    def error_handler_monitor_prefix
      'mhv-medical-records'
    end

    # Derives a metric namespace from the monitor prefix by replacing hyphens with underscores.
    # e.g. 'mhv-medical-records' → 'mhv_medical_records'
    def metric_namespace
      @metric_namespace ||= error_handler_monitor_prefix.tr('-', '_')
    end

    def monitor
      @monitor ||= Logging::Monitor.new(error_handler_monitor_prefix, allowlist: %i[error_class resource_name])
    end
  end
end
