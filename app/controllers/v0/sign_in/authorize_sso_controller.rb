# frozen_string_literal: true

module V0
  module SignIn
    class AuthorizeSSOController < ApplicationController
      skip_before_action :authenticate, only: :authorize_sso
      before_action :validate_authorize_sso_params, only: :authorize_sso
      before_action :authenticate_authorize_sso, only: :authorize_sso

      def authorize_sso
        return redirect_to_usip_for_prompt_login if prompt_login?

        redirect_url = authorize_sso_redirect_url(authorize_sso_user_code_map)

        ::SignIn::AuthorizeSSOContainer.delete(@authorize_sso_id) if @authorize_sso_id

        log_authorize_sso_success
        render body: redirect_url, content_type: 'text/html', status: :found
      rescue ::SignIn::Errors::MalformedParamsError => e
        handle_authorize_sso_error(e, :error)
      rescue => e
        handle_authorize_sso_error(e, :redirect)
      end

      private

      def authorize_sso_redirect_url(user_code_map)
        response_params = {
          code: user_code_map.login_code,
          type: user_code_map.type,
          state: user_code_map.client_state
        }.compact_blank

        ::SignIn::RedirectUrlGenerator.new(
          redirect_uri: user_code_map.client_config.redirect_uri,
          terms_code: user_code_map.terms_code,
          terms_redirect_uri: user_code_map.client_config.terms_of_use_url,
          params_hash: response_params
        ).perform
      end

      def authorize_sso_user_code_map
        code_challenge = authorize_sso_params[:code_challenge]
        code_challenge_method = authorize_sso_params[:code_challenge_method]
        client_state = authorize_sso_params[:state]
        nonce = authorize_sso_params[:nonce]
        app_name = authorize_sso_params[:app_name]
        user_attributes = ::SignIn::AuthSSO::SessionValidator.new(access_token:, client_id:).perform
        acr = user_attributes[:acr]
        type = user_attributes[:type]
        operation = ::SignIn::Constants::Auth::AUTHORIZE_SSO
        verified_icn = user_attributes[:icn]

        client_config = client_config(client_id)
        state_payload_jwt = ::SignIn::StatePayloadJwtEncoder.new(code_challenge:, code_challenge_method:, client_state:,
                                                                 acr:, type:, client_config:, operation:, nonce:,
                                                                 app_name:).perform

        state_payload = ::SignIn::StatePayloadJwtDecoder.new(state_payload_jwt:).perform

        ::SignIn::UserCodeMapCreator.new(user_attributes:, state_payload:, verified_icn:,
                                         request_ip: request.remote_ip).perform
      end

      def authorize_sso_params
        @authorize_sso_params ||= authorize_sso_container_params ||
                                  params.permit(:client_id, :code_challenge, :code_challenge_method, :state, :app_name,
                                                :nonce, :prompt)
      end

      def client_id
        authorize_sso_params[:client_id]
      end

      def authorize_sso_container_params
        @authorize_sso_id = params[:authorize_sso_id].presence
        return unless @authorize_sso_id

        container = ::SignIn::AuthorizeSSOContainer.find(@authorize_sso_id)
        return container.to_authorize_sso_params if container

        sign_in_logger.info('authorize sso request not found or expired', { authorize_sso_id: @authorize_sso_id })
        nil
      end

      def validate_authorize_sso_params
        validate_authorize_sso_params!
      rescue ::SignIn::Errors::MalformedParamsError => e
        handle_authorize_sso_error(e, :error)
      end

      def validate_authorize_sso_params!
        errors = [].tap do |err|
          err << 'client_id' if client_id.blank? || client_config(client_id).blank?
          err << 'prompt' unless valid_prompt?
          if pkce_client?
            err << 'code_challenge' if authorize_sso_params[:code_challenge].blank?

            unless authorize_sso_params[:code_challenge_method] == ::SignIn::Constants::Auth::CODE_CHALLENGE_METHOD
              err << 'code_challenge_method'
            end
          end
        end

        raise ::SignIn::Errors::MalformedParamsError.new(message: "Invalid params: #{errors.join(', ')}") if errors.any?
      end

      def pkce_client?
        client_config(authorize_sso_params[:client_id])&.auth_method_pkce?
      end

      def valid_prompt?
        prompt = authorize_sso_params[:prompt]
        prompt.blank? || ::SignIn::Constants::Auth::PROMPT_TYPES.include?(prompt)
      end

      def prompt_login?
        authorize_sso_params[:prompt] == ::SignIn::Constants::Auth::PROMPT_LOGIN
      end

      def redirect_to_usip_for_prompt_login
        sign_in_logger.info('authorize sso prompt login redirect', authorize_sso_log_params)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_AUTHORIZE_SSO_REDIRECT,
                         tags: authorize_sso_statsd_tags)
        redirect_to_usip
      end

      def redirect_to_usip
        stash_authorize_sso_request

        query_params = authorize_sso_params.to_h.merge(oauth: true)
        query_params[:authorize_sso_id] = @authorize_sso_id if @authorize_sso_id

        uri = URI.parse(IdentitySettings.sign_in.usip_uri)
        uri.query = query_params.to_query

        redirect_to uri, status: :found, allow_other_host: true
      rescue ::SignIn::Errors::MalformedParamsError => e
        log_authorize_sso_error(e, :error)
        handle_pre_login_error(e, client_id)
      end

      def stash_authorize_sso_request
        return if IdentitySettings.sign_in.sso_restricted_clients.include?(client_id)

        @authorize_sso_id = SecureRandom.uuid

        container = ::SignIn::AuthorizeSSOContainer.new(
          uuid: @authorize_sso_id,
          client_id:,
          code_challenge: authorize_sso_params[:code_challenge],
          code_challenge_method: authorize_sso_params[:code_challenge_method],
          client_state: authorize_sso_params[:state],
          app_name: authorize_sso_params[:app_name],
          nonce: authorize_sso_params[:nonce]
        )
        return if container.save

        raise ::SignIn::Errors::MalformedParamsError.new(
          message: "Invalid params: #{container.errors.full_messages.join(', ')}"
        )
      end

      def authenticate_authorize_sso
        access_token_authenticate(re_raise: true)
      rescue => e
        handle_authorize_sso_error(e, :redirect)
      end

      def handle_authorize_sso_error(error, handler)
        log_authorize_sso_error(error, handler)

        case handler
        when :error then handle_pre_login_error(error, client_id)
        when :redirect then redirect_to_usip
        end
      end

      def log_authorize_sso_success
        sign_in_logger.info('authorize sso', authorize_sso_log_params)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_AUTHORIZE_SSO_SUCCESS, tags: authorize_sso_statsd_tags)
      end

      def log_authorize_sso_error(error, handler)
        statsd_key = if handler == :redirect
                       ::SignIn::Constants::Statsd::STATSD_SIS_AUTHORIZE_SSO_REDIRECT
                     else
                       ::SignIn::Constants::Statsd::STATSD_SIS_AUTHORIZE_SSO_FAILURE
                     end

        context = authorize_sso_log_params.merge({ authorize_sso_id: @authorize_sso_id }).compact
        sign_in_logger.error("authorize sso #{handler}", exception: error, context:)
        StatsD.increment(statsd_key, tags: authorize_sso_statsd_tags)
      end

      def authorize_sso_log_params
        { client_id:, app_name: authorize_sso_params[:app_name] }
      end

      def authorize_sso_statsd_tags
        ["client_id:#{client_id}"]
      end
    end
  end
end
