# frozen_string_literal: true

module TravelPay
  module V0
    class AppointmentsController < ApplicationController
      include FeatureFlagHelper
      include ErrorHandling

      before_action :check_feature_flag

      def index
        monitor.log(:info, 'Travel Pay appointment search START')
        appointments = appointments_service.search_appointments(search_params)
        monitor.log(:info, 'Travel Pay appointment search END')
        monitor.track_request(:info, 'Appointments index success', 'travel_pay.appointments.index',
                              tags: ['result:success'])
        render json: { data: appointments }, status: :ok
      rescue => e
        monitor.track_request(:warn, 'Appointments index failure', 'travel_pay.appointments.index',
                              error: e.message, tags: ['result:failure'])
        raise
      end

      def create
        monitor.log(:info, 'Travel Pay appointment create START')
        appointment = appointments_service.create_appointment(create_params)
        monitor.log(:info, 'Travel Pay appointment create END')
        monitor.track_request(:info, 'Appointments create success', 'travel_pay.appointments.create',
                              tags: ['result:success'])
        render json: { data: appointment }, status: :created
      rescue => e
        monitor.track_request(:warn, 'Appointments create failure', 'travel_pay.appointments.create',
                              error: e.message, tags: ['result:failure'])
        raise
      end

      private

      def auth_manager
        @auth_manager ||= TravelPay::AuthManager.new(Settings.travel_pay.client_number, @current_user)
      end

      def appointments_service
        @appointments_service ||= TravelPay::AppointmentsService.new(auth_manager)
      end

      def check_feature_flag
        verify_feature_flag!(
          :travel_pay_enable_user_created_appointments,
          current_user,
          error_message: 'Travel Pay user-created appointments endpoint unavailable per feature toggle'
        )
      end

      def create_params
        params.permit(
          :facility_id,
          :appointment_name,
          :appointment_date_time,
          :completed
        ).to_h
      end

      def search_params
        params.permit(
          :has_claim,
          :external_appointment_id,
          :facility_id,
          :appointment_start_date,
          :appointment_end_date,
          :facility_name,
          :page_number,
          :page_size,
          :sort_field,
          :sort_direction
        ).to_h
      end
    end
  end
end
