# frozen_string_literal: true

require 'oracle_health/o_auth/configuration'
require 'oracle_health/o_auth/errors'

module OracleHealth
  module OAuth
    class Service < Common::Client::Base
      configuration Configuration

      def get_token
        Rails.logger.info("#{config.logging_prefix} get_token request")
        response = perform(:post, config.token_path, params, authenticated_header)
        body = response.body.is_a?(Hash) ? response.body : {}
        normalize_response_body(body)
      rescue Breakers::OutageException => e
        raise e
      rescue Common::Client::Errors::ClientError => e
        error = classify_error(e)
        code = error_code(e)
        error_message = e.message
        StatsD.increment("#{config.statsd_key_prefix}.get_token.failure", tags: ["error:#{code}"])
        Rails.logger.error("#{config.logging_prefix} get_token #{code}",
                           { error_message:, body: e.body, status: e.status })
        raise error
      rescue => e
        error_message = e.message
        StatsD.increment("#{config.statsd_key_prefix}.get_token.failure", tags: ["error:#{error_message}"])
        Rails.logger.error("#{config.logging_prefix} get_token #{error_message}", { error_message: })
        raise e
      end

      private

      def error_code(error)
        error.body.is_a?(Hash) ? error.body['error'] : nil
      end

      def classify_error(error)
        klass = if error.status.nil? || error.status >= 500
                  Errors::ServiceUnavailableError
                else
                  { 'invalid_client' => Errors::InvalidClientError,
                    'invalid_scope' => Errors::InvalidScopeError }.fetch(error_code(error), Errors::TokenError)
                end
        klass.new(error.message, error.status, error.body, headers: error.headers)
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
        {
          access_token: body['access_token'],
          scope: body['scope'],
          token_type: body['token_type'],
          expires_in: body['expires_in']
        }
      end
    end
  end
end
