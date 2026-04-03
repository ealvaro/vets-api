# frozen_string_literal: true

require 'debt_management_center/debts_service'

module Mobile
  module V0
    module DebtManagementCenter
      ##
      # Mobile-specific service for generating Overpay data
      # Inherits from DebtManagementCenter::DebtsService and overrides StatsD Prefix
      # to use mobile-specific analytics and monitoring
      #
      class DebtsService < ::DebtManagementCenter::DebtsService
        configuration ::DebtManagementCenter::DebtsConfiguration

        STATSD_KEY_PREFIX = 'api.dmc.mobile'
      end
    end
  end
end
