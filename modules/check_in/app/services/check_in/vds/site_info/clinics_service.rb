# frozen_string_literal: true

require 'common/exceptions'
require 'common/client/errors'
require 'oj'

module CheckIn
  module Vds
    module SiteInfo
      class ClinicsService < Common::Client::Base
        include Common::Client::Concerns::Monitoring
        include Vets::SharedLogging

        STATSD_KEY_PREFIX = 'api.check_in.vds_site_info.clinics'

        def get_clinics(site_id:)
          with_monitoring do
            response = perform(:get, clinics_url(site_id:), {}, headers)
            Oj.load(response.body)
          end
        end

        def config
          CheckIn::VAOS::Configuration.instance
        end

        private

        def clinics_url(site_id:)
          "/vds/info/v1/sites/#{site_id}/clinics"
        end

        def headers
          {
            'Content-Type' => 'application/json'
          }
        end
      end
    end
  end
end
