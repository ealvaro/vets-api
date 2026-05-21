# frozen_string_literal: true

require_relative 'service'
require_relative 'configuration'

module PagerDuty
  class ServicesClient < PagerDuty::Service
    configuration PagerDuty::Configuration

    # Probe each configured PagerDuty service individually by calling the
    # Get-a-Service endpoint to identify which setting (and which service ID)
    # is missing or misconfigured.
    # NOTE: This call is slow due to probing dozens of PagerDuty Services
    # It's intended to be called only when alerted of a bad service.
    # https://developer.pagerduty.com/api-reference
    def probe
      mapping = Settings.maintenance.services&.to_hash || {}
      mapping.map do |setting_name, service_id|
        { setting_name: setting_name.to_s }.merge(get_service(service_id))
      end
    end

    private

    def get_service(service_id)
      return { service_id: nil, status: nil } if service_id.nil?

      perform(:get, "services/#{service_id}", {})
      { service_id:, status: 200 }
    rescue => e
      { service_id:, status: e.respond_to?(:original_status) ? e.original_status : nil }
    end
  end
end
