# frozen_string_literal: true

module V0
  module SignIn
    class CallbackController < ApplicationController
      skip_before_action :authenticate, only: :callback

      def callback # rubocop:disable Metrics/MethodLength
        code = params[:code].presence
        state = params[:state].presence
        error = params[:error].presence

        validate_callback_params(code, state, error)

        state_payload = ::SignIn::StatePayloadJwtDecoder.new(state_payload_jwt: state).perform
        ::SignIn::StatePayloadVerifier.new(state_payload:).perform

        handle_credential_provider_error(error, state_payload&.type) if error
        service_token_response = auth_service(state_payload.type, state_payload.client_id).token(code)

        raise ::SignIn::Errors::CodeInvalidError.new message: 'Code is not valid' unless service_token_response

        user_info = auth_service(state_payload.type,
                                 state_payload.client_id).user_info(service_token_response[:access_token])
        credential_level = ::SignIn::CredentialLevelCreator.new(requested_acr: state_payload.acr,
                                                                type: state_payload.type,
                                                                logingov_acr: service_token_response[:logingov_acr],
                                                                user_info:).perform
        if credential_level.can_uplevel_credential?
          render_uplevel_credential(state_payload)
        else
          create_login_code(state_payload, user_info, credential_level)
        end
      rescue => e
        error_details = {
          type: state_payload&.type,
          client_id: state_payload&.client_id,
          acr: state_payload&.acr,
          operation: state_payload&.operation
        }
        error_details[:app_name] = state_payload.app_name if state_payload&.app_name
        sign_in_logger.error('callback error', exception: e, context: error_details)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_CALLBACK_FAILURE,
                         tags: ["type:#{error_details[:type]}",
                                "client_id:#{error_details[:client_id]}",
                                "acr:#{error_details[:acr]}",
                                "operation:#{error_details[:operation]}"])
        handle_pre_login_error(e, state_payload&.client_id)
      end

      private

      def validate_callback_params(code, state, error)
        raise ::SignIn::Errors::MalformedParamsError.new message: 'Code is not defined' unless code || error
        raise ::SignIn::Errors::MalformedParamsError.new message: 'State is not defined' unless state
      end

      def handle_credential_provider_error(error, type)
        if error == ::SignIn::Constants::Auth::ACCESS_DENIED
          error_message = 'User Declined to Authorize Client'
          error_code = if type == ::SignIn::Constants::Auth::LOGINGOV
                         ::SignIn::Constants::ErrorCode::LOGINGOV_VERIFICATION_DENIED
                       else
                         ::SignIn::Constants::ErrorCode::IDME_VERIFICATION_DENIED
                       end
          raise ::SignIn::Errors::AccessDeniedError.new message: error_message, code: error_code
        else
          error_message = 'Unknown Credential Provider Issue'
          error_code = ::SignIn::Constants::ErrorCode::GENERIC_EXTERNAL_ISSUE
          raise ::SignIn::Errors::CredentialProviderError.new message: error_message, code: error_code
        end
      end

      def render_uplevel_credential(state_payload)
        acr_for_type = ::SignIn::AcrTranslator.new(acr: state_payload.acr, type: state_payload.type,
                                                   uplevel: true).perform
        state = ::SignIn::StatePayloadJwtEncoder.new(code_challenge: state_payload.code_challenge,
                                                     code_challenge_method: ::SignIn::Constants::Auth::CODE_CHALLENGE_METHOD,
                                                     acr: state_payload.acr,
                                                     client_config: client_config(state_payload.client_id),
                                                     type: state_payload.type,
                                                     client_state: state_payload.client_state,
                                                     operation: state_payload.operation,
                                                     nonce: state_payload.nonce,
                                                     authorize_sso_id: state_payload.authorize_sso_id,
                                                     app_name: state_payload.app_name).perform
        render body: auth_service(state_payload.type, state_payload.client_id).render_auth(state:, acr: acr_for_type),
               content_type: 'text/html'
      end

      def create_login_code(state_payload, user_info, credential_level) # rubocop:disable Metrics/MethodLength
        user_attributes = auth_service(state_payload.type,
                                       state_payload.client_id).normalized_attributes(user_info, credential_level)
        verified_icn = ::SignIn::AttributeValidator.new(user_attributes:).perform
        user_code_map = ::SignIn::UserCodeMapCreator.new(
          user_attributes:, state_payload:, verified_icn:, request_ip: request.remote_ip
        ).perform

        context = {
          type: state_payload.type,
          client_id: state_payload.client_id,
          ial: credential_level.current_ial,
          acr: state_payload.acr,
          icn: verified_icn,
          credential_uuid: user_info.sub,
          authentication_time: Time.zone.now.to_i - state_payload.created_at,
          operation: state_payload.operation,
          safe_keys: [:icn]
        }
        context[:app_name] = state_payload.app_name if state_payload.app_name
        sign_in_logger.info('callback', context)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_CALLBACK_SUCCESS,
                         tags: ["type:#{state_payload.type}",
                                "client_id:#{state_payload.client_id}",
                                "ial:#{credential_level.current_ial}",
                                "acr:#{state_payload.acr}",
                                "operation:#{state_payload.operation}"])
        params_hash = { code: user_code_map.login_code, type: user_code_map.type }
        params_hash.merge!(state: user_code_map.client_state) if user_code_map.client_state.present?
        params_hash.merge!(authorize_sso_id: state_payload.authorize_sso_id) if state_payload.authorize_sso_id.present?

        render body: ::SignIn::RedirectUrlGenerator.new(
          redirect_uri: user_code_map.client_config.redirect_uri,
          terms_code: user_code_map.terms_code,
          terms_redirect_uri: user_code_map.client_config.terms_of_use_url,
          params_hash:
        ).perform,
               content_type: 'text/html'
      end
    end
  end
end
