# frozen_string_literal: true

require 'common/client/configuration/rest'

module SearchClickTracking
  class Configuration < Common::Client::Configuration::REST
    self.read_timeout = 30

    def base_path
      "#{Settings.search_click_tracking.url}/clicks/"
    end

    def service_name
      'SearchClickTracking'
    end

    def connection
      @connection ||= Faraday.new(base_path, request: { timeout: read_timeout }) do |conn|
        conn.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        conn.use(:breakers, service_name:)
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
