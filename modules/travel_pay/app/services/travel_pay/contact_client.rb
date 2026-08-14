# frozen_string_literal: true

require 'securerandom'
require_relative './base_client'

module TravelPay
  class ContactClient < TravelPay::BaseClient
    def initialize(auth_session)
      super()
      @auth_session = auth_session
    end

    ##
    # HTTP GET call to the BTSSS 'contacts/{contact_id}' endpoint
    # API responds with contact information for the given contact ID
    #
    # @return [Faraday::Response]
    #
    def get_contact
      log_to_statsd('contacts', 'get_contact') do
        connection(server_url: btsss_url).get(contact_path) do |req|
          req.headers['Authorization'] = bearer_token
          req.headers['BTSSS-Access-Token'] = access_token
          req.headers['X-Correlation-ID'] = correlation_id
          req.headers.merge!(claim_headers)
        end
      end
    end

    private

    def contact_path
      "api/v3/contacts/#{@auth_session.contact_id}"
    end

    def bearer_token
      "Bearer #{@auth_session.veis_token}"
    end

    def access_token
      @auth_session.btsss_token
    end

    def btsss_url
      Settings.travel_pay.base_url
    end

    def correlation_id
      cid = SecureRandom.uuid
      monitor.log(:info, 'Correlation ID', correlation_id: cid)
      cid
    end
  end
end
