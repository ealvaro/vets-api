# frozen_string_literal: true

module Mobile
  module V0
    class VeteranStatusCardsController < ApplicationController
      def show
        if Settings.vsp_environment&.to_s&.downcase != 'production' &&
           @current_user&.email == 'vets.gov.user+5@gmail.com'
          raise Common::Exceptions::BackendServiceException.new(
            'VETSCARD_500',
            { detail: 'System error occurred' },
            500
          )
        end

        render json: service.status_card
      rescue => e
        Rails.logger.error("Mobile::VeteranStatusCardsController unexpected error: #{e.message}",
                           backtrace: e.backtrace)
        render json: { error: 'An unexpected error occurred' }, status: :internal_server_error
      end

      private

      def service
        @service ||= ::Mobile::V0::VeteranStatusCard::Service.new(@current_user)
      end
    end
  end
end
