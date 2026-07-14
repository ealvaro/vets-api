# frozen_string_literal: true

module FacilitiesApi
  module V2
    module PPMS
      module Middleware
        class PPMSParser < Faraday::Middleware
          # Upstream statuses we want surfaced as their own client-error type rather
          # than collapsed into a generic bad gateway. When PPMS returns a blank error
          # code, these become PPMS_404 / PPMS_429 (see exceptions.en.yml) so the
          # controller renders 404 / 429; every other status falls back to PPMS_502.
          PASSTHROUGH_STATUSES = [404, 429].freeze

          def on_complete(env)
            env.body = parse_body(env)
          end

          private

          def parse_body(env)
            hsh = JSON.parse(env.body).with_indifferent_access

            if hsh['error'] && hsh['error']['message'].match?(/No (Provider|Facility)/)
              env[:status] = 200
              hsh['value'] = []
              hsh
            elsif hsh['error']
              # Set code so it matches a key in exceptions.en.yml
              hsh['error']['code'] = error_code_for(env.status) if hsh['error']['code'].blank?
              hsh['error']['detail'] = hsh['error']['message']
              hsh['error']['source'] = hsh.dig('error', 'innererror', 'message')
              hsh['error']
            else
              hsh
            end
          end

          def error_code_for(status)
            PASSTHROUGH_STATUSES.include?(status) ? "_#{status}" : '_502'
          end
        end
      end
    end
  end
end
