# frozen_string_literal: true

require 'common/client/base'
require 'dgi/letters/configuration'
require 'dgi/service'
require 'authentication_token_service'

module MebApi
  module DGI
    module Letters
      class Service < MebApi::DGI::Service
        configuration MebApi::DGI::Letters::Configuration
        STATSD_KEY_PREFIX = 'api.dgi.status'

        def get_claim_letter(claimant_id, type = 'Chapter33')
          type ||= 'Chapter33'

          with_monitoring do
            headers = request_headers
            options = { timeout: 60 }
            perform(:get, end_point(claimant_id, type), {}, headers, options)
          end
        end

        def get_claim_letter_by_claim_id(claim_id, claimant_id, type)
          type = get_mapped_type(type)

          with_monitoring do
            headers = request_headers
            options = { timeout: 60 }
            perform(:get, claim_letter_by_claim_id_endpoint(claim_id, claimant_id, type), {}, headers, options)
          end
        end

        private

        def end_point(claimant_id, type)
          "claimant/#{claimant_id}/claimType/#{type}/letter"
        end

        def claim_letter_by_claim_id_endpoint(claim_id, claimant_id, type)
          "claimant/#{claimant_id}/claim/#{claim_id}/claimType/#{type}/letter"
        end

        def request_headers
          {
            Accept: 'application/pdf',
            Authorization: "Bearer #{MebApi::AuthenticationTokenService.call}",
            'Accept-Encoding': 'gzip, deflate, br',
            Connection: 'keep-alive'
          }
        end

        def get_mapped_type(type)
          case type
          when 'CH33'
            'Chapter33'
          when 'CH30'
            'Chapter30'
          when 'CH1606'
            'Chapter1606'
          when 'CH35'
            'Chapter35'
          when 'Fry'
            'Fry'
          when 'Toe'
            'toe'
          else
            type
          end
        end
      end
    end
  end
end
