# frozen_string_literal: true

module TravelPay
  module V0
    class FacilitiesController < ApplicationController
      include FeatureFlagHelper
      include ErrorHandling

      before_action :check_feature_flag

      def index
        contact_response = contact_client.get_contact
        home_facility_id = contact_response.body.dig('data', 'homeFacility', 'id')

        if home_facility_id.blank?
          contact_id_prefix = auth_session.contact_id.to_s.first(8)
          Rails.logger.warn("TravelPay: contact #{contact_id_prefix}... has no home facility assigned")
          return render json: { error: 'No home facility found for this user' }, status: :not_found
        end

        facilities_response = facilities_client.get_related_facilities(home_facility_id, permitted_params)
        render json: facilities_response.body, status: facilities_response.status
      rescue Common::Exceptions::BackendServiceException => e
        raise if unified_error_handling_enabled?

        Rails.logger.error("TravelPay: BTSSS error retrieving facilities: #{e.message}")
        render json: { error: 'Error retrieving facilities' }, status: e.original_status
      rescue Faraday::Error => e
        raise if unified_error_handling_enabled?

        TravelPay::ServiceError.raise_mapped_error(e)
      end

      private

      def permitted_params
        params.permit(:page_number, :page_size, :sort_field, :sort_direction, :station_number, :name).to_h
      end

      def auth_session
        @auth_session ||= auth_manager.authorize
      end

      def auth_manager
        @auth_manager ||= TravelPay::AuthManager.new(Settings.travel_pay.client_number, @current_user)
      end

      def contact_client
        @contact_client ||= TravelPay::ContactClient.new(auth_session)
      end

      def facilities_client
        @facilities_client ||= TravelPay::FacilitiesClient.new(auth_session)
      end

      def check_feature_flag
        verify_feature_flag!(
          :travel_pay_enable_user_created_appointments,
          @current_user,
          error_message: 'Travel Pay facilities endpoint unavailable per feature toggle'
        )
      end
    end
  end
end
