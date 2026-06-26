# frozen_string_literal: true

require 'sign_in/logingov/service'

module SignIn
  class LogoutRedirectGenerator
    attr_reader :credential_type, :client_config, :post_logout_redirect_uri

    def initialize(client_config:, credential_type: nil, post_logout_redirect_uri: nil)
      @credential_type = credential_type
      @client_config = client_config
      @post_logout_redirect_uri = post_logout_redirect_uri
    end

    def perform
      return if redirect_uri.blank?

      if authenticated_with_logingov?
        logingov_service.render_logout(client_config.client_id, redirect_uri)
      else
        URI.parse(redirect_uri).to_s
      end
    end

    private

    def redirect_uri
      @redirect_uri ||= valid_post_logout_redirect_uri? ? post_logout_redirect_uri : logout_redirect_uri
    end

    def logout_redirect_uri
      client_config&.logout_redirect_uri
    end

    def valid_post_logout_redirect_uri?
      return false if post_logout_redirect_uri.blank? || logout_redirect_uri.blank?

      same_redirect_base?(post_logout_redirect_uri, logout_redirect_uri)
    end

    def same_redirect_base?(requested, registered)
      requested_uri = URI.parse(requested)
      registered_uri = URI.parse(registered)

      requested_uri.scheme == registered_uri.scheme &&
        requested_uri.host == registered_uri.host &&
        requested_uri.port == registered_uri.port &&
        requested_uri.path == registered_uri.path
    rescue URI::InvalidURIError
      false
    end

    def authenticated_with_logingov?
      credential_type == Constants::Auth::LOGINGOV
    end

    def logingov_service
      AuthenticationServiceRetriever.new(type: Constants::Auth::LOGINGOV).perform
    end
  end
end
