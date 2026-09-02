# frozen_string_literal: true

require 'oracle_health/o_auth/configuration'
require 'oracle_health/o_auth/errors'

module OracleHealth
  module OAuth
    class Service < Common::Client::Base
      TOKEN_EXPIRY_BUFFER = 30
      ERROR_CODE_CLASS_MAP = {
        'invalid_client' => Errors::InvalidClientError,
        'invalid_scope' => Errors::InvalidScopeError
      }.freeze

      configuration Configuration

      def get_token
        Rails.cache.fetch(token_cache_key) do |_key, options|
          request_and_cache_token(options)
        end
      rescue Common::Client::Errors::ClientError => e
        error = classify_error(e)
        StatsD.increment("#{config.statsd_key_prefix}.get_token.failure")
        Rails.logger.error("#{config.logging_prefix} get_token error",
                           { error_message: e.message, body: e.body, status: e.status })
        raise error
      rescue => e
        StatsD.increment("#{config.statsd_key_prefix}.get_token.failure")
        Rails.logger.error("#{config.logging_prefix} get_token error", { error_message: e.message })
        raise e
      end

      private

      def classify_error(error)
        klass = if error.is_a?(Errors::ValidationError)
                  Errors::ValidationError
                elsif error.status.nil? || error.status >= 500
                  Errors::ServiceUnavailableError
                else
                  ERROR_CODE_CLASS_MAP.fetch(oauth_error_identifier(error), Errors::TokenError)
                end
        klass.new(error.message, error.status, error.body, headers: error.headers)
      end

      def oauth_error_identifier(error)
        error.body.is_a?(Hash) ? error.body['error'] : nil
      end

      def params
        URI.encode_www_form(
          grant_type: 'client_credentials',
          scope:
        )
      end

      def authenticated_header
        {
          'Authorization' => "Basic #{Base64.strict_encode64("#{config.client_id}:#{config.client_secret}")}",
          'Content-Type' => 'application/x-www-form-urlencoded',
          'Accept' => 'application/json'
        }
      end

      def scope
        'system/Patient.read system/Patient.write'
      end

      def normalize_response_body(body)
        raise Errors::ValidationError, 'Invalid token response body' unless body.is_a?(Hash)
        unless body['expires_in'].to_i > TOKEN_EXPIRY_BUFFER
          raise Errors::ValidationError,
                "Invalid token response: expires_in must be greater than #{TOKEN_EXPIRY_BUFFER} seconds"
        end

        {
          access_token: body['access_token'],
          scope: body['scope'],
          token_type: body['token_type'],
          expires_in: body['expires_in']
        }
      end

      def token_cache_key
        "oracle_health_oauth_token_#{config.tenant_id}"
      end

      def request_and_cache_token(cache_options)
        Rails.logger.info("#{config.logging_prefix} get_token request")
        response = perform(:post, config.token_path, params, authenticated_header)
        result = normalize_response_body(response.body)
        cache_options.expires_in = result[:expires_in].to_i - TOKEN_EXPIRY_BUFFER
        Rails.logger.info("#{config.logging_prefix} get_token success", expires_in: result[:expires_in])
        result
      end
    end
  end
end
