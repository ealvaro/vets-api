# frozen_string_literal: true

require 'common/client/configuration/base'

module SearchKendra
  class Configuration < Common::Client::Configuration::Base
    def service_name
      'SearchKendra/Results'
    end

    def index_id
      Settings.search_kendra.index_id
    end

    def region
      Settings.search_kendra.region
    end

    def client
      @client ||= Aws::Kendra::Client.new(region:)
    end
  end
end
