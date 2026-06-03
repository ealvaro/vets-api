# frozen_string_literal: true

module V0
  module SignIn
    class ReviewInstanceCallbackProxyController < ApplicationController
      skip_before_action :authenticate, only: :review_instance_callback_proxy

      def review_instance_callback_proxy
        code = params[:code].presence
        state = params[:state].presence
        error = params[:error].presence

        raise ::SignIn::Errors::MalformedParamsError.new message: 'State is not defined' unless state

        state_payload = ::SignIn::StatePayloadJwtDecoder.new(state_payload_jwt: state).perform

        unless state_payload.redirect_uri
          raise ::SignIn::Errors::MalformedParamsError.new message: 'Redirect URI is not defined'
        end

        sign_in_logger.info('review instance callback proxy', { redirect_uri: state_payload.redirect_uri })

        render body: ::SignIn::RedirectUrlGenerator.new(
          redirect_uri: state_payload.redirect_uri,
          params_hash: { code:, state:, error: }.compact
        ).perform, content_type: 'text/html'
      rescue => e
        sign_in_logger.error('review instance callback proxy error', exception: e)
        render json: { errors: e }, status: :bad_request
      end
    end
  end
end
