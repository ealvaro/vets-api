# frozen_string_literal: true

require 'sign_in/clear/code_container'
require 'sign_in/clear/configuration'
require 'sign_in/oauth/service'

module SignIn
  module Clear
    class Service < SignIn::OAuth::Service
      configuration Configuration

      private

      def default_acr
        OAuth::Constants::CLEAR_IAL2
      end

      def auth_params(_acr, state, _operation, **)
        base_auth_params(state).merge(
          scope: config.scope,
          code_challenge: generate_code_challenge(state),
          code_challenge_method: config.code_challenge_method
        )
      end

      def token_params(code, state)
        {
          grant_type: config.grant_type,
          code:,
          redirect_uri: config.redirect_uri,
          client_id: config.client_id,
          client_secret: config.client_secret,
          code_verifier: retrieve_code_verifier(state)
        }
      end

      def token_content_type
        'application/x-www-form-urlencoded'
      end

      def parse_token_response(response_body)
        { access_token: response_body[:access_token], id_token: response_body[:id_token] }
      end

      def userinfo_path(access_token)
        "#{config.userinfo_path}/#{verification_id_from_token(access_token)}"
      end

      def userinfo_params
        { reveal_sensitive_data: true }
      end

      def parse_user_info(response)
        body = response.body
        traits = body[:traits] || {}

        OAuth::UserInfo.new(
          sub: body[:user_id],
          email: traits[:email],
          first_name: traits[:first_name],
          middle_name: traits[:middle_name],
          last_name: traits[:last_name],
          ssn: traits[:ssn9],
          birth_date: format_birth_date(traits[:dob]),
          phone_number: traits[:phone],
          address: normalize_address(traits[:address])
        )
      end

      def credential_attributes(user_info)
        {
          clear_uuid: user_info.sub,
          ssn: user_info.ssn,
          birth_date: user_info.birth_date,
          first_name: user_info.first_name,
          middle_name: user_info.middle_name,
          last_name: user_info.last_name,
          phone_number: user_info.phone_number,
          address: user_info.address,
          multifactor: true,
          service_name: config.service_name
        }
      end

      def get_authn_context(_current_ial)
        OAuth::Constants::CLEAR_IAL2
      end

      def generate_code_challenge(state)
        code_verifier = SecureRandom.urlsafe_base64(64)
        CodeContainer.new(state:, code_verifier:).save!

        code_challenge(code_verifier)
      end

      def code_challenge(code_verifier)
        Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
      end

      def retrieve_code_verifier(state)
        container = CodeContainer.find(state)
        raise OAuth::Errors::CodeVerifierNotFoundError, "#{config.log_prefix} Code verifier not found" if container.nil?

        container.code_verifier.tap { container.destroy }
      end

      def verification_id_from_token(access_token)
        verification_id = JWT.decode(access_token, nil, false).first['verification_id']
        if verification_id.blank?
          raise OAuth::Errors::JWTDecodeError, "#{config.log_prefix} verification_id missing from access token"
        end

        verification_id
      rescue JWT::DecodeError
        raise OAuth::Errors::JWTDecodeError, "#{config.log_prefix} Access token is malformed"
      end

      def normalize_address(address)
        return if address.blank?

        {
          street: address[:line1],
          street2: address[:line2],
          postal_code: address[:postal_code],
          state: address[:state],
          city: address[:city],
          country: address[:country] == 'US' ? USA_COUNTRY_CODE : address[:country]
        }
      end

      def format_birth_date(dob)
        return if dob.blank?

        Date.new(dob[:year], dob[:month], dob[:day]).strftime('%Y-%m-%d')
      end
    end
  end
end
