# frozen_string_literal: true

require 'sign_in/clear/code_container'
require 'sign_in/clear/configuration'
require 'sign_in/clear/errors'
require 'sign_in/credential_attributes_digester'

module SignIn
  module Clear
    class Service < Common::Client::Base
      configuration Configuration

      def render_auth(state: SecureRandom.hex, operation: Constants::Auth::AUTHORIZE)
        Rails.logger.info(
          "[SignIn][Clear][Service] Rendering auth, state: #{state}, operation: #{operation}"
        )
        code_verifier = SecureRandom.urlsafe_base64(64)
        CodeContainer.new(state:, code_verifier:).save!
        RedirectUrlGenerator.new(
          redirect_uri: auth_url,
          params_hash: auth_params(state, code_challenge(code_verifier))
        ).perform
      end

      def token(code, state)
        code_verifier = retrieve_code_verifier(state)
        response = perform(:post, config.token_path, token_params(code, code_verifier),
                           { 'Content-Type' => 'application/x-www-form-urlencoded' })
        Rails.logger.info("[SignIn][Clear][Service] Token Success, code: #{code}")
        parse_token_response(response.body)
      rescue Common::Client::Errors::ClientError => e
        raise_client_error(e, 'Token')
      end

      def user_info(access_token)
        verification_id = verification_id_from_token(access_token)
        response = perform(:get, config.verification_session_path(verification_id),
                           { reveal_sensitive_data: true },
                           { 'Authorization' => "Bearer #{access_token}" })
        OpenStruct.new(response.body.merge(sub: response.body[:user_id]))
      rescue Common::Client::Errors::ClientError => e
        raise_client_error(e, 'UserInfo')
      end

      def normalized_attributes(user_info, credential_level)
        traits = user_info.traits || {}

        {
          clear_uuid: user_info.user_id,
          current_ial: credential_level.current_ial,
          max_ial: credential_level.max_ial,
          ssn: traits[:ssn9]&.tr('-', ''),
          birth_date: format_birth_date(traits[:dob]),
          first_name: traits[:first_name],
          middle_name: traits[:middle_name],
          last_name: traits[:last_name],
          phone_number: traits[:phone],
          address: normalize_address(traits[:address]),
          csp_email: traits[:email],
          multifactor: true,
          service_name: config.service_name,
          authn_context: Constants::Auth::CLEAR_IAL2,
          auto_uplevel: credential_level.auto_uplevel
        }.tap { |attrs| attrs[:digest] = digest_credential_attributes(attrs) }
      end

      private

      def verification_id_from_token(access_token)
        verification_id = JWT.decode(access_token, nil, false).first['verification_id']
        if verification_id.blank?
          raise Errors::JWTDecodeError, '[SignIn][Clear][Service] verification_id missing from access token'
        end

        verification_id
      rescue JWT::DecodeError
        raise Errors::JWTDecodeError, '[SignIn][Clear][Service] Access token is malformed'
      end

      def normalize_address(address)
        return if address.blank?

        {
          street: address[:line1],
          street2: address[:line2],
          postal_code: address[:postal_code],
          state: address[:state],
          city: address[:city],
          country: address[:country] == 'US' ? 'USA' : address[:country]
        }
      end

      def format_birth_date(dob)
        return if dob.blank?

        Date.new(dob[:year], dob[:month], dob[:day]).strftime('%Y-%m-%d')
      end

      def auth_url = "#{config.base_path}/#{config.auth_path}"

      def auth_params(state, code_challenge)
        {
          client_id: config.client_id,
          redirect_uri: config.redirect_uri,
          response_type: config.response_type,
          scope: config.scope,
          state:,
          code_challenge:,
          code_challenge_method: config.code_challenge_method
        }
      end

      def token_params(code, code_verifier)
        URI.encode_www_form(
          grant_type: config.grant_type,
          code:,
          redirect_uri: config.redirect_uri,
          client_id: config.client_id,
          client_secret: config.client_secret,
          code_verifier:
        )
      end

      def parse_token_response(response_body)
        { access_token: response_body[:access_token], id_token: response_body[:id_token] }
      end

      def code_challenge(code_verifier)
        Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
      end

      def retrieve_code_verifier(state)
        container = CodeContainer.find(state)
        raise Errors::CodeVerifierNotFoundError, '[SignIn][Clear][Service] Code verifier not found' if container.nil?

        container.code_verifier.tap { container.destroy }
      end

      def raise_client_error(client_error, function_name)
        status = client_error.status
        description = client_error.body && client_error.body[:error]
        raise client_error, "[SignIn][Clear][Service] Cannot perform #{function_name} request, " \
                            "status: #{status}, description: #{description}"
      end

      def digest_credential_attributes(attributes)
        SignIn::CredentialAttributesDigester.new(
          credential_uuid: attributes[:clear_uuid], first_name: attributes[:first_name],
          last_name: attributes[:last_name], ssn: attributes[:ssn],
          birth_date: attributes[:birth_date], email: attributes[:csp_email]
        ).perform
      end
    end
  end
end
