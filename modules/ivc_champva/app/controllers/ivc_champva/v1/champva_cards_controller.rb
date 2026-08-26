# frozen_string_literal: true

module IvcChampva
  module V1
    class ChampvaCardsController < ApplicationController
      skip_after_action :set_csrf_header

      NOT_ENROLLED_MESSAGE = 'We could not find a CHAMPVA enrollment for this account.'
      UPSTREAM_MESSAGE = 'We could not retrieve your CHAMPVA card details. Please try again later.'
      MISSING_ICN_MESSAGE = 'Your account is missing the information needed to look up CHAMPVA enrollment.'

      def get_benefits_card
        return render_not_found unless Flipper.enabled?(:champva_benefits_card, current_user)
        return render_missing_icn if current_user.icn.blank?

        render_card_result(IvcChampva::ChampvaEligibilityService.benefits_card_for(current_user))
      end

      private

      def render_card_result(result)
        case result[:status]
        when :ok
          render json: { data: { type: 'champva_card', attributes: result[:attributes] } }, status: :ok
        when :not_enrolled
          render json: { error: { code: 'not_enrolled', message: NOT_ENROLLED_MESSAGE } }, status: :not_found
        when :upstream_timeout
          render json: { error: { code: 'upstream_timeout', message: UPSTREAM_MESSAGE } }, status: :gateway_timeout
        else
          render json: { error: { code: 'upstream_error', message: UPSTREAM_MESSAGE } }, status: :bad_gateway
        end
      end

      def render_not_found
        render json: { error_message: 'Not found' }, status: :not_found
      end

      def render_missing_icn
        render json: { error: { code: 'missing_icn', message: MISSING_ICN_MESSAGE } }, status: :unprocessable_content
      end
    end
  end
end
