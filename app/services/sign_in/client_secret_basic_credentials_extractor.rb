# frozen_string_literal: true

module SignIn
  class ClientSecretBasicCredentialsExtractor
    attr_reader :request, :grant_type, :client_id

    def initialize(request:, grant_type:, client_id:)
      @request = request
      @grant_type = grant_type
      @client_id = client_id
    end

    def perform
      return {} unless authorization_code_grant?
      return {} unless ActionController::HttpAuthentication::Basic.has_basic_credentials?(request)

      decoded_client_id, decoded_client_secret = decoded_basic_credentials
      validate_client_id_param!(decoded_client_id)

      { client_id: decoded_client_id, client_secret: decoded_client_secret }
    rescue Errors::StandardError => e
      context = { grant_type:, client_id: }.compact
      sign_in_logger.error('error', exception: e, context:)
      raise
    end

    private

    def authorization_code_grant?
      grant_type == Constants::Auth::AUTH_CODE_GRANT
    end

    def decoded_basic_credentials
      decoded_client_id, decoded_client_secret = Base64.strict_decode64(encoded_credentials).split(':', 2)
      raise malformed_header_error if decoded_client_id.blank? || decoded_client_secret.blank?

      [decoded_client_id, decoded_client_secret]
    rescue ArgumentError
      raise malformed_header_error
    end

    def encoded_credentials
      ActionController::HttpAuthentication::Basic.auth_param(request).to_s
    end

    def validate_client_id_param!(decoded_client_id)
      return if client_id.blank? || client_id == decoded_client_id

      raise Errors::MalformedParamsError.new(message: 'Client id is not valid')
    end

    def malformed_header_error
      Errors::MalformedParamsError.new(message: 'Authorization header is malformed')
    end

    def sign_in_logger
      @sign_in_logger ||= Logger.new(prefix: self.class)
    end
  end
end
