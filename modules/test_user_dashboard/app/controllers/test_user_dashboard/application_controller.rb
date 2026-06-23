# frozen_string_literal: true

require 'vets/shared_logging'

module TestUserDashboard
  class ApplicationController < ActionController::API
    include Vets::SharedLogging
    include Traceable

    before_action :set_request_context

    def require_jwt
      token = request.headers['JWT']
      pub_key = request.headers['PK']

      head :forbidden unless valid_token(token, pub_key)
    end

    private

    def valid_token(token, pub_key)
      return false unless token && pub_key

      rsa_public = OpenSSL::PKey::RSA.new(Base64.decode64(pub_key))
      raw_token = token.gsub('Bearer ', '')
      begin
        JWT.decode raw_token, rsa_public, true, { algorithm: 'RS256' }
        return true
      rescue JWT::DecodeError => e
        Rails.logger.error('Error decoding TUD JWT: ', body: e.message)
      end
      false
    end

    def set_request_context
      RequestStore.store['additional_request_attributes'] = { 'source' => 'test-user-dashboard' }
    end
  end
end
