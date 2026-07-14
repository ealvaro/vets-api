# frozen_string_literal: true

require 'lighthouse/benefits_discovery/service'

module BenefitsDiscovery
  class GatewayController < ApplicationController
    service_tag 'bds-gateway'

    before_action :check_flipper_enabled, only: [:recommendations]

    STATSD_KEY_PREFIX = 'api.bds_gateway.proxy'

    def recommendations
      validate_source_app_header_presence!
      validate_user_profile!

      tags = request_tags
      StatsD.increment("#{STATSD_KEY_PREFIX}.request", tags:)

      response_data = fetch_recommendations

      StatsD.increment("#{STATSD_KEY_PREFIX}.success", tags:)
      render json: response_data
    rescue => e
      log_proxy_error(e)
      raise
    end

    private

    def shared_credentials
      api_key = Settings.lighthouse.benefits_discovery.x_api_key.to_s.presence
      app_id = Settings.lighthouse.benefits_discovery.x_app_id.to_s.presence

      if api_key.blank? || app_id.blank?
        raise Common::Exceptions::ServiceUnavailable, detail: 'BDS gateway credentials are not configured'
      end

      { api_key:, app_id: }
    end

    def validate_user_profile!
      raise Common::Exceptions::Forbidden, detail: 'User ICN is required' if current_user&.icn.blank?
    end

    def fetch_recommendations
      service = ::BenefitsDiscovery::Service.new(**shared_credentials)
      service.fetch_v1_recommendations(
        icn: current_user.icn,
        date_of_birth: current_user.birth_date
      )
    end

    def validate_source_app_header_presence!
      raise Common::Exceptions::Unauthorized if request.headers['Source-App-Name'].blank?
    end

    def log_proxy_error(error, path: request.path.delete_prefix('/'))
      method = request.method
      tags = ["path:#{path}", "method:#{method}", "error:#{error.class}"]

      StatsD.increment("#{STATSD_KEY_PREFIX}.error", tags:)
      Rails.logger.error("Benefits Discovery Gateway proxy error: #{error.message}", path:, method:)
    end

    def request_tags
      ["path:#{request.path.delete_prefix('/')}", "method:#{request.method}"]
    end

    def check_flipper_enabled
      raise Common::Exceptions::RoutingError, request.path unless Flipper.enabled?(:bds_gateway_enabled)
    end
  end
end
