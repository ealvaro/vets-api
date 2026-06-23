# frozen_string_literal: true

module Mobile
  class ApplicationController < SignIn::ApplicationController
    include Traceable
    include SignIn::AudienceValidator

    service_tag 'mobile-app'
    validates_access_token_audience [IdentitySettings.sign_in.vamobile_client_id,
                                     ('vamock-mobile' if MockedAuthentication.mockable_env?)]

    before_action :authenticate
    before_action :set_request_context
    skip_before_action :authenticate, only: :cors_preflight

    private

    attr_reader :current_user

    def authenticate
      raise_unauthorized('Missing Authorization header') if request.headers['Authentication-Method'].blank?
      return super if sis_authentication?

      raise_unauthorized('Authentication method not supported')
    end

    def sis_authentication?
      request.headers['Authentication-Method'] == 'SIS'
    end

    def raise_unauthorized(detail)
      raise Common::Exceptions::Unauthorized.new(detail:)
    end

    def set_request_context
      RequestStore.store['additional_request_attributes'] = { 'source' => 'mobile' }
    end
  end
end
