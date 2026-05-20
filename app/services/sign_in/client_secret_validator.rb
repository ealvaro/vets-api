# frozen_string_literal: true

module SignIn
  class ClientSecretValidator
    attr_reader :client_id, :client_secret, :client_config

    def initialize(client_id:, client_secret:, client_config:)
      @client_id = client_id
      @client_secret = client_secret
      @client_config = client_config
    end

    def perform
      validate!

      true
    rescue Errors::StandardError => e
      context = { client_id:, client_config_client_id: client_config&.client_id }.compact
      sign_in_logger.error('error', exception: e, context:)
      raise
    end

    private

    def validate!
      invalid_client! if client_id.blank?
      invalid_client! if client_secret.blank?
      invalid_client! if client_config.blank?
      invalid_client! unless client_id == client_config.client_id
      invalid_client! unless client_config.authenticate_client_secret(client_secret)
    end

    def invalid_client!
      raise Errors::ClientSecretInvalidError.new(message: 'Client secret is not valid')
    end

    def sign_in_logger
      @sign_in_logger ||= Logger.new(prefix: self.class)
    end
  end
end
