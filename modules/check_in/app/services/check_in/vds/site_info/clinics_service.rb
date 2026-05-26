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
        rescue Common::Exceptions::BackendServiceException => e
          log_vds_clinics_fetch_failure(site_id:, error: e)
          raise
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

        def log_vds_clinics_fetch_failure(site_id:, error:)
          Rails.logger.info('HCE-Check-In') do
            "appointments_vds_clinics_fetch_failed site_id=#{site_id} " \
              "error=#{error.class} status=#{error.try(:status)}"
          end
        end
      end
    end
  end
end
