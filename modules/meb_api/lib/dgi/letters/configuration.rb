# frozen_string_literal: true

require 'dgi/configuration'
require 'faraday/multipart'
require 'common/client/middleware/response/raise_custom_error'

module MebApi
  module DGI
    module Letters
      class Configuration < Common::Client::Configuration::REST
        def base_path
          Settings.dgi.vets.url.to_s
        end

        def connection
          flag_enabled = Flipper.enabled?(:dgi_meb_rudisill_flow_partition)

          # Clear connection if flag state has changed to enable hot rollback
          @conn = nil if @flag_state && @flag_state != flag_enabled
          @flag_state = flag_enabled

          @conn ||= Faraday.new(base_path, headers: base_request_headers, request: request_options) do |faraday|
            faraday.use(:breakers, service_name:)
            faraday.request :multipart

            # Use enhanced error handling with custom codes only if feature flag enabled
            # Otherwise use standard Faraday error handling to maintain compatibility
            # Place error handling before betamocks to wrap it and prevent bypasses
            if @flag_state
              faraday.response :raise_custom_error, error_prefix: 'DGI'
            else
              faraday.use Faraday::Response::RaiseError
            end

            faraday.response :betamocks if mock_enabled?
            faraday.response :json, content_type: /\bjson/
            faraday.adapter Faraday.default_adapter
          end
        end

        def service_name
          'DGI/Letters'
        end

        def mock_enabled?
          Settings.dgi.vets.mock || false
        end
      end
    end
  end
end
