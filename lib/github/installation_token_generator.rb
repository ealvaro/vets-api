# frozen_string_literal: true

require 'octokit'
require 'jwt'

module Github
  class InstallationTokenGenerator
    JWT_TTL = 540

    def initialize(app_id:, private_key:, api_endpoint:)
      raise ArgumentError, 'app_id is required' if app_id.blank?
      raise ArgumentError, 'private_key is required' if private_key.blank?
      raise ArgumentError, 'api_endpoint is required' if api_endpoint.blank?

      @app_id = app_id
      @private_key = parse_private_key(private_key)
      @api_endpoint = api_endpoint
    end

    def generate(org:)
      raise ArgumentError, 'org is required' if org.blank?

      client = app_client
      installation = client.find_organization_installation(org)
      client.create_app_installation_access_token(
        installation.id, accept: 'application/vnd.github+json'
      )[:token]
    end

    private

    def app_client
      Octokit::Client.new(bearer_token: app_jwt, api_endpoint: @api_endpoint)
    end

    def parse_private_key(private_key)
      OpenSSL::PKey::RSA.new(private_key)
    rescue OpenSSL::PKey::PKeyError, ArgumentError
      raise ArgumentError, 'private_key is invalid'
    end

    def app_jwt
      now = Time.now.to_i
      claims = { iat: now - 60, exp: now + JWT_TTL, iss: @app_id }
      JWT.encode(claims, @private_key, 'RS256')
    end
  end
end
