# frozen_string_literal: true

require 'faraday'
require 'json'

module DocumentClassifier
  module VAGptClient
    class RequestError < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        @status = status
        super(message)
      end
    end

    class Client
      def initialize(connection:, api_version:, responses_path:)
        @connection = connection
        @api_version = api_version
        @responses_path = responses_path
      end

      def responses = self

      def create(parameters:)
        response = @connection.post(@responses_path) do |request|
          request.params['api-version'] = @api_version
          request.body = parameters
        end
        response.body.is_a?(String) ? JSON.parse(response.body) : response.body
      rescue Faraday::Error => e
        raise_request_error(e, status: e.response_status)
      rescue JSON::ParserError => e
        raise_request_error(e)
      end

      private

      def raise_request_error(error, status: nil)
        message = ['VA GPT request failed', ("status=#{status}" if status)].compact.join(' ')
        raise RequestError.new(message, status:), cause: error
      end
    end

    module_function

    def build
      Config.validate!
      Client.new(
        connection: build_connection,
        api_version: Config.api_version,
        responses_path: Config.responses_path
      )
    end

    def build_connection
      Faraday.new(
        url: Config.base_url,
        headers: { 'api-key' => Config.api_key },
        request: { open_timeout: Config.open_timeout, timeout: Config.read_timeout }
      ) do |faraday|
        faraday.request :json
        faraday.use Faraday::Response::RaiseError
        faraday.response :json, content_type: /\bjson/
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
