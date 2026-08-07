# frozen_string_literal: true

require 'faraday'
require 'common/client/errors'
require 'common/models/collection'

module Common
  module Client
    ##
    # Raised if the Faraday adapter is a Faraday::Adapter::HTTPClient and the
    # Common::Client::Middleware::Request::RemoveCookies middleware in not included.
    #
    class SecurityError < StandardError
    end

    ##
    # Raised when the breakers Faraday middleware is not first in the stack.
    #
    class BreakersImplementationError < StandardError
    end

    ##
    # Base class for creating HTTP services. Wraps the Faraday gem and is configured via by passing in a
    # {Common::Client::Configuration::REST} or {Common::Client::Configuration::SOAP} depending on the type
    # of service you're connecting to. Once configured requests are made via the `perform` method.
    #
    # @example Create a service and make a GET request
    #   class MyService < Common::Client::Base
    #     configuration MyConfiguration
    #
    #     def get_resource
    #       perform(:get, '/api/v1/resource')
    #     end
    #   end
    #
    #   service = MyService.new
    #   response = service.get_resource
    #
    # @example a POST request with a body, headers, and Faraday options
    #   def post_resource(json)
    #     headers = { 'Content-Type' => 'application/json' }
    #     options = { timeout: 60 }
    #     response = perform(:post, '/submit', json, headers, options)
    #   end
    #
    class Base
      ##
      # Sets the configuration singleton to use
      #
      def self.configuration(configuration = nil)
        @configuration ||= configuration.instance
      end

      def raise_backend_exception(key, source, error = nil)
        raise Common::Exceptions::BackendServiceException.new(
          key,
          { source: source.to_s },
          error&.status,
          error&.body
        )
      end

      private

      def config
        self.class.configuration
      end

      def service_name
        config.service_name
      end

      def connection
        @connection ||= lambda do
          connection = config.connection
          validate_base_url!(connection)
          handlers = connection.builder.handlers

          if connection.builder.adapter == Faraday::Adapter::HTTPClient &&
             handlers.exclude?(Common::Client::Middleware::Request::RemoveCookies)
            raise SecurityError, 'http client needs cookies stripped'
          end

          if handlers.include?(Breakers::UptimeMiddleware)
            if handlers.first == Breakers::UptimeMiddleware
              message = "Please pass a service_name argument to the Breakers middleware for service: #{service_name}"
              warn(message) unless connection.app.service_name
              return connection
            end

            raise BreakersImplementationError, 'Breakers should be the first middleware implemented.'
          else
            warn("Breakers is not implemented for service: #{service_name}")
          end

          connection
        end.call
      end

      # Fails fast with a clear, actionable message when a service's base URL is
      # not absolute (missing scheme or host). A blank or scheme-less host Setting
      # (e.g. a Parameter Store value missing the `https://` prefix) otherwise
      # surfaces much later as a cryptic `URI::BadURIError: both URI are relative`
      # from deep inside Faraday's URL merging. Test-adapter connections used in
      # specs are skipped since they intentionally omit a real base URL.
      def validate_base_url!(connection)
        return if connection.builder.adapter == Faraday::Adapter::Test

        url_prefix = connection.url_prefix
        return if url_prefix&.scheme.present? && url_prefix&.host.present?

        raw_base_url = config.try(:base_path)
        raise Common::Client::Errors::ConfigurationError,
              "Invalid base URL for service '#{service_name}': expected an absolute URL with a scheme and host, " \
              "got #{raw_base_url.inspect} (parsed as #{url_prefix.to_s.inspect}). Verify the service's host Setting " \
              '(e.g. the Parameter Store value must include the scheme, such as https://).'
      end

      def perform(method, path, params, headers = nil, options = nil)
        raise NoMethodError, "#{method} not implemented" unless config.request_types.include?(method)

        send(method, path, params || {}, headers || {}, options || {})
      end

      def request(method, path, params = {}, headers = {}, options = {}) # rubocop:disable Metrics/MethodLength
        Datadog::Tracing.active_span&.set_tag('common_client_service', service_name)
        sanitize_headers!(method, path, params, headers)
        raise_not_authenticated if headers.keys.include?('Token') && headers['Token'].nil?
        connection.send(method.to_sym, path, params) do |request|
          request.headers.update(headers)
          options.each { |option, value| request.options.send("#{option}=", value) }
        end.env
      rescue Common::Exceptions::BackendServiceException => e
        raise config.service_exception.new(
          e.key, e.response_values, e.original_status, e.original_body
        )
      rescue Timeout::Error, Faraday::TimeoutError => e
        raise Common::Exceptions::GatewayTimeout, e.class.name
      rescue Faraday::ClientError, Faraday::ServerError, Faraday::Error => e
        error_class = case e
                      when Faraday::ParsingError
                        Common::Client::Errors::ParsingError
                      else
                        Common::Client::Errors::ClientError
                      end

        response_hash = e.response&.to_hash
        client_error = error_class.new(e.message, response_hash&.dig(:status), response_hash&.dig(:body),
                                       headers: response_hash&.dig(:headers))
        raise client_error
      end

      def sanitize_headers!(_method, _path, _params, headers)
        headers.transform_keys!(&:to_s)

        headers.transform_values! do |value|
          if value.nil?
            ''
          else
            value
          end
        end
      end

      def get(path, params, headers, options)
        request(:get, path, params, headers, options)
      end

      def post(path, params, headers, options)
        request(:post, path, params, headers, options)
      end

      def put(path, params, headers, options)
        request(:put, path, params, headers, options)
      end

      def delete(path, params, headers, options)
        request(:delete, path, params, headers, options)
      end

      def raise_not_authenticated
        raise Common::Client::Errors::NotAuthenticated, 'Not Authenticated'
      end
    end
  end
end
