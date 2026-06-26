# frozen_string_literal: true

require 'sign_in/logingov/service'
require 'public_suffix'

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
      @redirect_uri ||= if valid_post_logout_redirect_uri?
                          logout_redirect_uri_with_post_logout
                        else
                          logout_redirect_uri
                        end
    end

    def logout_redirect_uri
      client_config&.logout_redirect_uri
    end

    def valid_post_logout_redirect_uri?
      return false if post_logout_redirect_uri.blank? || logout_redirect_uri.blank?

      requested_host = uri_host(post_logout_redirect_uri)
      configured_host = uri_host(logout_redirect_uri)
      return false if requested_host.blank? || configured_host.blank?
      return true if requested_host == configured_host

      requested_domain = domain(requested_host)
      requested_domain.present? && requested_domain == domain(configured_host)
    end

    def uri_host(uri)
      URI.parse(uri).host
    rescue URI::InvalidURIError
      nil
    end

    def domain(host)
      PublicSuffix.domain(host)
    rescue PublicSuffix::Error
      nil
    end

    def logout_redirect_uri_with_post_logout
      return logout_redirect_uri if post_logout_redirect_uri.blank?

      uri = URI.parse(logout_redirect_uri)
      uri.query = { post_logout_redirect_uri: }.to_query
      uri.to_s
    end

    def authenticated_with_logingov?
      credential_type == Constants::Auth::LOGINGOV
    end

    def logingov_service
      AuthenticationServiceRetriever.new(type: Constants::Auth::LOGINGOV).perform
    end
  end
end
