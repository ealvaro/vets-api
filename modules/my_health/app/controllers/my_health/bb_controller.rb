# frozen_string_literal: true

require 'bb/client'

module MyHealth
  ##
  # Base controller for Blue Button (BB) health records features.
  #
  # Provides the MHV Blue Button client and authorization against the
  # +:mhv_health_records+ policy. Subclassed by controllers that expose
  # extract status, eligible data classes, and Blue Button report downloads.
  #
  class BBController < ApplicationController
    include MyHealth::MHVControllerConcerns
    service_tag 'mhv-medical-records'

    protected

    def client
      @client ||= BB::Client.new(session: { user_id: current_user.mhv_correlation_id })
    end

    def authorize
      raise_access_denied unless current_user.authorize(:mhv_health_records, :access?)
    end

    def raise_access_denied
      raise Common::Exceptions::Forbidden, detail: 'You do not have access to health records'
    end
  end
end
