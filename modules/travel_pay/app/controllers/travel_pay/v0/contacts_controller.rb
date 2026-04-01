# frozen_string_literal: true

module TravelPay
  module V0
    class ContactsController < ApplicationController
      rescue_from Common::Exceptions::BackendServiceException, with: :render_backend_service_exception

      def show
        contact = client.get_contact
        render json: contact.body, status: contact.status
      end

      private

      def auth_session
        auth_manager.authorize
      end

      def auth_manager
        @auth_manager ||= TravelPay::AuthManager.new(Settings.travel_pay.client_number, @current_user)
      end

      def client
        @client ||= TravelPay::ContactClient.new(auth_session)
      end

      def render_backend_service_exception(e)
        message = "TravelPay: BTSSS error retrieving contact: #{e.message}"
        Rails.logger.error(message)
        render json: { error: 'Error retrieving contact' }, status: e.original_status
      end
    end
  end
end
