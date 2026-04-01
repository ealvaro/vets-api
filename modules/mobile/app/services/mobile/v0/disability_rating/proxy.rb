# frozen_string_literal: true

require 'common/exceptions'

module Mobile
  module V0
    module DisabilityRating
      class Proxy
        def initialize(icn)
          @icn = icn
        end

        # Fetches rated disabilities from the Lighthouse Veteran Verification API.
        def get_rated_disabilities
          settings = Settings.lighthouse.veteran_verification['form526']

          response = veteran_verification_service.get_rated_disabilities(
            @icn,
            settings.access_token.client_id,
            settings.access_token.rsa_key
          )

          unless response.is_a?(Hash)
            detail = response.try(:message) || 'Lighthouse veteran verification service unavailable'
            raise Common::Exceptions::ServiceUnavailable.new(detail:)
          end

          response['data']['attributes']
        rescue Common::Exceptions::ExternalServerInternalServerError => e
          detail = e.try(:detail)
          raise Common::Exceptions::BadGateway.new(detail:)
        rescue Common::Exceptions::BaseError
          raise
        rescue Faraday::ConnectionFailed, Faraday::TimeoutError
          raise Common::Exceptions::ServiceUnavailable
        end

        private

        def veteran_verification_service
          VeteranVerification::Service.new
        end
      end
    end
  end
end
