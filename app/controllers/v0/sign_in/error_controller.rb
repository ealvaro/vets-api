# frozen_string_literal: true

module V0
  module SignIn
    class ErrorController < ApplicationController
      skip_before_action :authenticate, only: :error

      def error
        error_code = params[:error_code].presence || ::SignIn::Constants::ErrorCode::INVALID_REQUEST
        request_id = params[:request_id].presence || request.request_id
        occurred_at = Integer(params[:occurred_at], exception: false) if params[:occurred_at].present?
        redirect_uri = client_config(params[:client_id].presence)&.logout_redirect_uri

        render body: ::SignIn::ErrorPageRenderer.new(error_code:, request_id:, redirect_uri:, occurred_at:).perform,
               content_type: 'text/html'
      end
    end
  end
end
