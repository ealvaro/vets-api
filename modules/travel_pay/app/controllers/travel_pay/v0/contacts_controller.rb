# frozen_string_literal: true

module TravelPay
  module V0
    class ContactsController < ApplicationController
      include ErrorHandling

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
    end
  end
end
