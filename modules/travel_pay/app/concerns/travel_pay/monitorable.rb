# frozen_string_literal: true

require 'travel_pay/monitor'

module TravelPay
  module Monitorable
    extend ActiveSupport::Concern

    private

    def monitor
      @monitor ||= TravelPay::Monitor.new
    end
  end
end
