# frozen_string_literal: true

module V0
  module SignIn
    class AuthorizeController < ApplicationController
      skip_before_action :authenticate, only: :authorize

      def authorize # rubocop:disable Metrics/MethodLength
        type = params[:type].presence
        client_state = params[:state].presence
        code_challenge = params[:code_challenge].presence
        code_challenge_method = params[:code_challenge_method].presence
        client_id = params[:client_id].presence
        acr = params[:acr].presence
        operation = params[:operation].presence || ::SignIn::Constants::Auth::AUTHORIZE
        scope = params[:scope].presence
        nonce = params[:nonce].presence
        authorize_sso_id = params[:authorize_sso_id].presence
        app_name = params[:app_name].presence
        context = { type:, client_id:, acr:, operation:, authorize_sso_id: }.compact
        context[:app_name] = app_name if app_name

        validate_authorize_params(type, client_id, acr, operation)

        delete_cookies if token_cookies

        acr_for_type = ::SignIn::AcrTranslator.new(acr:, type:).perform
        state = ::SignIn::StatePayloadJwtEncoder.new(code_challenge:,
                                                     code_challenge_method:,
                                                     acr:,
                                                     client_config: client_config(client_id),
                                                     type:,
                                                     operation:,
                                                     client_state:,
                                                     scope:,
                                                     nonce:,
                                                     authorize_sso_id:,
                                                     app_name:).perform

        sign_in_logger.info('authorize', context)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_AUTHORIZE_SUCCESS,
                         tags: ["type:#{type}", "client_id:#{client_id}", "acr:#{acr}", "operation:#{operation}"])

        auth_url = auth_service(type, client_id).render_auth(state:, acr: acr_for_type, operation:)
        render body: ::SignIn::RedirectUrlGenerator.new(redirect_uri: auth_url).perform,
               content_type: 'text/html'
      rescue => e
        sign_in_logger.error('authorize error', exception: e,
                                                context: { client_id:, type:, acr:, operation: }
                                                .merge({ app_name: }.compact))
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_AUTHORIZE_FAILURE)
        handle_pre_login_error(e, client_id)
      end

      private

      def validate_authorize_params(type, client_id, acr, operation)
        if client_config(client_id).blank?
          raise ::SignIn::Errors::MalformedParamsError.new message: 'Client id is not valid'
        end
        unless client_config(client_id).valid_credential_service_provider?(type)
          raise ::SignIn::Errors::MalformedParamsError.new message: 'Type is not valid'
        end
        if type == ::SignIn::Constants::Auth::CLEAR && !IdentitySettings.clear.enabled
          raise ::SignIn::Errors::MalformedParamsError.new message: 'Type is not valid'
        end
        unless ::SignIn::Constants::Auth::OPERATION_TYPES.include?(operation)
          raise ::SignIn::Errors::MalformedParamsError.new message: 'Operation is not valid'
        end
        unless client_config(client_id).valid_service_level?(acr)
          raise ::SignIn::Errors::MalformedParamsError.new message: 'ACR is not valid'
        end
      end
    end
  end
end
