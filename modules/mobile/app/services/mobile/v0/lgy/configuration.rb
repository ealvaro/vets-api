# frozen_string_literal: true

require 'lgy/configuration'

module Mobile
  module V0
    module Lgy
      ##
      # HTTP client configuration for {Mobile::V0::Lgy::Service}, sets the
      # mobile-specific appId and apiKey so LGY can differentiate mobile traffic
      # from web traffic in production.
      #
      # For now the base_path and service_name are unchanged, i.e. this is a
      # shared service with distinct credentials.
      #
      class Configuration < ::LGY::Configuration
        ##
        # @return [String] mobile appId set in `settings.yml` via credstash
        #
        def app_id
          Settings.lgy_mobile.app_id
        end

        ##
        # @return [String] mobile apiKey set in `settings.yml` via credstash
        #
        def api_key
          Settings.lgy_mobile.api_key
        end
      end
    end
  end
end
