# frozen_string_literal: true

module TravelPay
  module V0
    class AppointmentsController < ApplicationController
      include FeatureFlagHelper

      before_action :check_feature_flag

      def index
        Rails.logger.info(message: 'Travel Pay appointment search START')

        appointments = appointments_service.search_appointments(search_params)

        Rails.logger.info(message: 'Travel Pay appointment search END')

        render json: { data: appointments }, status: :ok
      rescue Faraday::Error => e
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
