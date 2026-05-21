# frozen_string_literal: true

require 'pagerduty/services_client'

module V0
  class MaintenanceWindowDiagnosticsController < ApplicationController
    service_tag 'maintenance-windows'
    skip_before_action :authenticate

    # This call is slow due to probing dozens of PagerDuty Services
    # It's intended to be called only when alerted of a bad service.
    def index
      results = PagerDuty::ServicesClient.new.probe
      bad = results.reject { |r| r[:status].nil? || r[:status] == 200 }
      render json: { results:, bad: }
    end
  end
end
