# frozen_string_literal: true

require 'common/client/configuration/rest'

module Auth
  module ClientCredentials
    ##
    # HTTP client configuration for the {Auth::ClientCredentials::Service},
    # sets the base path, the base request headers, and a service name for breakers and metrics.
    #
    class Configuration < Common::Client::Configuration::REST
      self.read_timeout = 20

      # @return [Hash] The basic headers required for any token service API call.
      def self.base_request_headers
        super.merge({ 'Content-Type': 'application/x-www-form-urlencoded' })
      end

      # @return [Config::Options] Settings for client_credentials API.
      def settings
        Settings.lighthouse.auth.client_credentials
      end

      # @return [Faraday::Response] The response containing data needed to make further API calls.
      def get_access_token(url, body)
        connection.post(url, URI.encode_www_form(body))
      end

      # Creates a Faraday connection with parsing json and adding breakers functionality.
      #
      # @return [Faraday::Connection] a Faraday connection instance.
      def connection
        options = {
          headers: base_request_headers,
          request: request_options,
          ssl: { verify: verify_ssl? }
        }
        @conn ||= Faraday.new(**options) do |faraday|
          faraday.use      :breakers
          faraday.use      Faraday::Response::RaiseError

          faraday.response :json

          faraday.adapter Faraday.default_adapter
        end
      end

      # @return [Boolean] Should the service verify SSL certificates.
      def verify_ssl?
        value = settings.verify_ssl
        value = true if value.nil?
        ActiveModel::Type::Boolean.new.cast(value)
      end

      # breakers will be tripped if error rate exceeds the threshold over a two minute period.
      def breakers_error_threshold
        value = settings.breakers_error_threshold.to_i
        value.positive? ? value : 80
      end
    end
  end
end
