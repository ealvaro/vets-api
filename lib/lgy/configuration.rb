# frozen_string_literal: true

require 'common/client/configuration/rest'

module LGY
  class Configuration < Common::Client::Configuration::REST
    def connection
      @conn ||= Faraday.new(base_path, headers: base_request_headers, request: request_options) do |faraday|
        faraday.use(:breakers, service_name:)
        faraday.use Faraday::Response::RaiseError
        faraday.response :betamocks if mock_enabled?
        faraday.response :snakecase, symbolize: false
        faraday.response :json, content_type: /\bjson/
        faraday.adapter Faraday.default_adapter
      end
    end

    def mock_enabled?
      Settings.lgy.mock_coe || false
    end

    def base_path
      Settings.lgy.base_url
    end

    # @return [String] the LGY app id
    def app_id
      Settings.lgy.app_id
    end

    # @return [String] the LGY api key
    def api_key
      Settings.lgy.api_key
    end

    # @return [String] the LGY SAHSHA app id
    def sahsha_app_id
      Settings.lgy_sahsha.app_id
    end

    # @return [String] the LGY SAHSHA api key
    def sahsha_api_key
      Settings.lgy_sahsha.api_key
    end

    def service_name
      'LoanGuaranty'
    end
  end
end
