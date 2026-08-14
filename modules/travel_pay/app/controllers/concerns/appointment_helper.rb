# frozen_string_literal: true

module AppointmentHelper
  extend ActiveSupport::Concern

  def find_or_create_appt_id!(claim_type, params = {})
    monitor.log(:info, "#{claim_type} claim: Get appt by date time: #{params['appointment_date_time']}")
    appt = appts_service.find_or_create_appointment(params)

    if appt.nil? || appt[:data].nil?
      msg = "No appointment found for #{params['appointment_date_time']}"
      monitor.track_request(:error, msg, 'travel_pay.appointments.find_or_create.not_found')
      raise Common::Exceptions::ResourceNotFound, detail: msg
    end

    appt[:data]['id']
  end

  private

  def auth_manager
    @auth_manager ||= TravelPay::AuthManager.new(Settings.travel_pay.client_number, @current_user)
  end

  def appts_service
    @appts_service ||= TravelPay::AppointmentsService.new(auth_manager)
  end
end
