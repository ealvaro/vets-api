# frozen_string_literal: true

require 'common/client/configuration/rest'
require 'common/client/middleware/request/camelcase'
require 'common/client/middleware/request/multipart_request'
require 'common/client/middleware/response/json_parser'
require 'common/client/middleware/response/raise_custom_error'
require 'common/client/middleware/response/mhv_errors'
require 'common/client/middleware/response/snakecase'
require 'faraday/multipart'

module AAL
  class Configuration < Common::Client::Configuration::REST
    def base_path
      "#{Settings.mhv.api_gateway.hosts.usermgmt}/v1/"
    end

    ##
    # @return [String] Service name to use in breakers and metrics
    #
    def service_name
      'AAL'
    end

    ##
    # @return [Faraday::Connection] a Faraday connection instance
    #
    def connection
      Faraday.new(base_path, headers: base_request_headers, request: request_options) do |conn|
        conn.use(:breakers, service_name:)
        conn.use Betamocks::Middleware if ActiveModel::Type::Boolean.new.cast(mock?)
        conn.request :multipart_request
        conn.request :multipart
        conn.request :camelcase
        conn.request :json

        # Uncomment this if you want curl command equivalent or response output to log
        # conn.request(:curl, ::Logger.new(STDOUT), :warn) unless Rails.env.production?
        # conn.response(:logger, ::Logger.new(STDOUT), bodies: true) unless Rails.env.production?

        conn.response :raise_custom_error, error_prefix: service_name
        conn.response :mhv_errors
        conn.response :mhv_xml_html_errors
        conn.response :json_parser

        conn.adapter Faraday.default_adapter
      end
    end

    ##
    # Whether Betamocks should mock this configuration's HTTP calls. Overridden per
    # subclass to read that product's own settings namespace, so enabling one
    # product's mock flag never affects the others. The base is namespace-agnostic
    # and defaults to disabled.
    #
    # @return [Boolean, String, nil] raw mock setting; cast to Boolean by #connection
    #
    def mock?
      false
    end
  end

  class MRConfiguration < Configuration
    def app_token
      Settings.mhv.medical_records.app_token
    end

    def x_api_key
      Settings.mhv.medical_records.x_api_key
    end

    def mock?
      Settings.mhv.medical_records&.mock
    end
  end

  class RXConfiguration < Configuration
    def app_token
      Settings.mhv.rx.app_token
    end

    def x_api_key
      Settings.mhv.rx.x_api_key
    end

    def mock?
      Settings.mhv.rx&.mock
    end
  end

  class SMConfiguration < Configuration
    def app_token
      Settings.mhv.sm.app_token
    end

    def x_api_key
      Settings.mhv.sm.x_api_key
    end

    def mock?
      Settings.mhv.sm&.mock
    end
  end

  class AALConfiguration < Configuration
    def app_token
      Settings.mhv.aal.app_token
    end

    def x_api_key
      Settings.mhv.aal.x_api_key
    end

    def mock?
      Settings.mhv.aal&.mock
    end
  end
end
