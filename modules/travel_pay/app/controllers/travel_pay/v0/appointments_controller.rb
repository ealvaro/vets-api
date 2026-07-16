# frozen_string_literal: true

module TravelPay
  module V0
    class AppointmentsController < ApplicationController
      include FeatureFlagHelper
      include ErrorHandling

      before_action :check_feature_flag

      def index
        Rails.logger.info(message: 'Travel Pay appointment search START')
        appointments = appointments_service.search_appointments(search_params)
        Rails.logger.info(message: 'Travel Pay appointment search END')
        render json: { data: appointments }, status: :ok
      rescue Common::Exceptions::BackendServiceException => e
        raise if unified_error_handling_enabled?

        Rails.logger.error("TravelPay: BTSSS error searching appointments: #{e.message}")
        render json: { error: 'Error searching appointments' }, status: e.original_status
      rescue Faraday::Error => e
        raise if unified_error_handling_enabled?

        TravelPay::ServiceError.raise_mapped_error(e)
      end

      def create
        Rails.logger.info(message: 'Travel Pay appointment create START')
        appointment = appointments_service.create_appointment(create_params)
        Rails.logger.info(message: 'Travel Pay appointment create END')
        render json: { data: appointment }, status: :created
      rescue Common::Exceptions::BackendServiceException => e
        raise if unified_error_handling_enabled?

        Rails.logger.error("TravelPay: BTSSS error creating appointment: #{e.message}")
        render json: { error: 'Error creating appointment' }, status: e.original_status
      rescue Faraday::Error => e
        raise if unified_error_handling_enabled?

        TravelPay::ServiceError.raise_mapped_error(e)
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
