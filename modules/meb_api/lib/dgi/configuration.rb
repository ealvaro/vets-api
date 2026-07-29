# frozen_string_literal: true

require 'common/client/middleware/response/raise_custom_error'

module MebApi
  module DGI
    class Configuration < Common::Client::Configuration::REST
      def connection
        flag_enabled = Flipper.enabled?(:dgi_meb_rudisill_flow_partition)

        # Clear connection if flag state has changed to enable hot rollback
        @conn = nil if @flag_state && @flag_state != flag_enabled
        @flag_state = flag_enabled

        @conn ||= Faraday.new(base_path, headers: base_request_headers, request: request_options) do |faraday|
          faraday.use(:breakers, service_name:)
          faraday.request :json

          # Use enhanced error handling with custom codes only if feature flag enabled
          # Otherwise use standard Faraday error handling to maintain compatibility
          # Place error handling before betamocks/snakecase to wrap them and prevent bypasses
          if @flag_state
            faraday.response :raise_custom_error, error_prefix: 'DGI'
          else
            faraday.use Faraday::Response::RaiseError
          end

          faraday.response :betamocks if mock_enabled?
          faraday.response :snakecase, symbolize: false
          faraday.response :json, content_type: /\bjson/ # ensures only json content types parsed
          faraday.adapter Faraday.default_adapter
        end
      end

      def base_path
        Settings.dgi.vets.url.to_s
      end

      def service_name
        'DGI'
      end

      def mock_enabled?
        # subclass to override
        false
      end
    end
  end
end
