# frozen_string_literal: true

require 'digital_forms_api/configuration'
require 'digital_forms_api/jwt_generator'
require 'digital_forms_api/monitor'
require 'digital_forms_api/validation'
require 'common/client/base'

module DigitalFormsApi
  module Service
    # Base service class for API
    class Base < ::Common::Client::Base
      configuration DigitalFormsApi::Configuration

      include DigitalFormsApi::Validation

      def initialize
        # assigning configuration here so subclass will inherit
        self.class.configuration DigitalFormsApi::Configuration
        super
      end

      # @see Common::Client::Base#perform
      def perform(method, path, params, headers = {}, options = {})
        start_time = Time.current
        code = reason = nil

        call_location = caller_locations.first # eg. DigitalFormsApi::Service::Files#upload
        headers = headers.merge(request_headers)
        requested_api = endpoint || path.split('/').first

        response = super(method, path, params, headers, options) # returns Faraday::Env
        code = response.try(:status) || 200
        reason = response.reason_phrase

        response
      rescue => e
        code = e.try(:status) || 500
        reason = parse_error(e)

        raise e
      ensure
        duration = (Time.current - start_time) * 1000.0 # milliseconds
        monitor.track_api_request(method, requested_api, code, reason, duration, call_location:, **context)
        @context = {} # reset the request context so later tracking is not polluted
      end

      # GET retrieve the openapi.json for FormsAPI
      # @return [Hash] the parsed JSON
      def openapi
        perform(:get, "#{root}/openapi.json", {}, {}).body
      rescue => e
        Rails.logger.warn("DigitalFormsApi::Service::Base#openapi fallback to local schema: #{e.message}")
        JSON.parse(File.read("#{DigitalFormsApi::MODULE_PATH}/schema/openapi.json"))
      end

      private

      # create the monitor to be used for _this_ instance
      # @see DigitalFormsApi::Monitor::Service
      def monitor
        @monitor ||= DigitalFormsApi::Monitor::Service.new
      end

      # additional request headers
      def request_headers
        { 'Authorization' => "Bearer #{encode_jwt}" }
      end

      # @return [String] the encoded jwt
      def encode_jwt
        DigitalFormsApi::JwtGenerator.encode_jwt
      end

      # the name for _this_ endpoint
      def endpoint
        nil
      end

      # a context to accompany the logging for a request
      # @see DigitalFormsApi::Monitor::Service#track_api_request
      def context
        @context.is_a?(Hash) ? @context : {}
      end

      # Build a request context with StatsD tags derived from the given keys
      # @param tags [Hash] key-value pairs to use as both context and StatsD tags
      # @return [Hash] context hash with a nested :tags key for StatsD
      def build_context(**tags)
        tags.merge(tags:)
      end

      # extract the root (shema://host) from the api base url
      def root
        api = URI.parse(Settings.digital_forms_api.base_url)
        api.path = '' # reduce the url to the true root
        api.to_s
      end

      # parse the request error
      def parse_error(error)
        body = error.try(:body)
        messages = if body.is_a?(Hash) && body['messages'].is_a?(Array)
                     body['messages'].filter_map { |message| message.is_a?(Hash) ? message['text'] : nil }
                   end
        reason = messages&.first || (body.is_a?(Hash) && body['message']) || error.message

        @context = context.merge(error: messages || reason)

        reason
      end
    end

    # end Service
  end

  # end DigitalFormsApi
end
