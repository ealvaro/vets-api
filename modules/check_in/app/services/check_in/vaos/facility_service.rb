# frozen_string_literal: true

require 'common/exceptions'
require 'common/client/errors'
require 'json'
require 'memoist'
require 'vets/shared_logging'

module CheckIn
  module VAOS
    class FacilityService < Common::Client::Base
      include Vets::SharedLogging
      include Common::Client::Concerns::Monitoring

      STATSD_KEY_PREFIX = 'api.check_in.vaos.facilities'

      def get_facility_with_cache(facility_id:)
        Rails.cache.fetch(facility_cache_key(facility_id), expires_in: 12.hours) do
          get_facility(facility_id:)
        end
      end

      def get_facility(facility_id:)
        with_monitoring do
          response = perform(:get, facilities_url(facility_id:), {}, headers)
          Oj.load(response.body).with_indifferent_access
        end
      rescue Common::Exceptions::BackendServiceException => e
        log_facility_fetch_failure(facility_id:, error: e)
        raise
      end

      def track_vds_clinics_skipped_flag_off!
        return unless facilities_v3_enabled? && !vds_site_info_clinics_enabled?

        StatsD.increment(CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_SKIPPED_FLAG_OFF)
        Rails.logger.info('HCE-Check-In') do
          'appointments_vds_clinics_skipped_flag_off facilities_v3_enabled=true vds_site_info_clinics_enabled=false'
        end
      end

      def get_clinic_with_cache(facility_id:, clinic_id:)
        if facilities_v3_enabled?
          return nil unless vds_site_info_clinics_enabled?

          clinics = Rails.cache.fetch(vds_site_clinics_cache_key(facility_id), expires_in: 12.hours) do
            vds_site_info_clinics_service.get_clinics(site_id: facility_id)
          end
          clinic_from_vds_list(clinics, clinic_id, site_id: facility_id)
        else
          Rails.cache.fetch("check_in.vaos_clinic_#{facility_id}_#{clinic_id}", expires_in: 12.hours) do
            get_clinic(facility_id:, clinic_id:)
          end
        end
      end

      def get_clinic(facility_id:, clinic_id:)
        if facilities_v3_enabled?
          return nil unless vds_site_info_clinics_enabled?

          clinics = vds_site_info_clinics_service.get_clinics(site_id: facility_id)
          clinic_from_vds_list(clinics, clinic_id, site_id: facility_id)
        else
          with_monitoring do
            response = perform(:get, clinics_url(facility_id:, clinic_id:), {}, headers)
            Oj.load(response.body).with_indifferent_access
          end
        end
      end

      def config
        CheckIn::VAOS::Configuration.instance
      end

      private

      def clinic_from_vds_list(clinics, clinic_id, site_id:)
        vds_clinic = VdsClinicMapper.find_by_clinic_ien(clinics, clinic_id)
        return VdsClinicMapper.to_clinic_info(vds_clinic) if vds_clinic

        log_vds_clinic_lookup_miss(site_id:, clinic_id:, clinics:)
        nil
      end

      def log_vds_clinic_lookup_miss(site_id:, clinic_id:, clinics:)
        reason = clinics.blank? ? 'empty_site_list' : 'clinic_ien_not_found'
        StatsD.increment(CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_LOOKUP_MISS, tags: ["reason:#{reason}"])
        Rails.logger.info('HCE-Check-In') do
          "appointments_vds_clinic_lookup_miss site_id=#{site_id} clinic_id=#{clinic_id} reason=#{reason}"
        end
      end

      def vds_site_info_clinics_service
        @vds_site_info_clinics_service ||= CheckIn::Vds::SiteInfo::ClinicsService.new
      end

      def vds_site_clinics_cache_key(facility_id)
        "check_in.vds_site_clinics_#{facility_id}"
      end

      def facility_cache_key(facility_id)
        if facilities_v3_enabled?
          "check_in.vaos_facility_v3_#{facility_id}"
        else
          "check_in.vaos_facility_#{facility_id}"
        end
      end

      def facilities_v3_enabled?
        Flipper.enabled?(:check_in_experience_va_mobile_facilities_v3_enabled)
      end

      def vds_site_info_clinics_enabled?
        Flipper.enabled?(:check_in_experience_vds_site_info_clinics_enabled)
      end

      def facilities_url(facility_id:)
        if facilities_v3_enabled?
          "/facilities/v3/facilities/#{facility_id}/"
        else
          "/facilities/v2/facilities/#{facility_id}"
        end
      end

      # MFS v2 clinic-by-id; used when facilities v3 (migrated path) is not enabled.
      def clinics_url(facility_id:, clinic_id:)
        "/facilities/v2/facilities/#{facility_id}/clinics/#{clinic_id}"
      end

      def headers
        {
          'Content-Type' => 'application/json'
        }
      end

      def log_facility_fetch_failure(facility_id:, error:)
        Rails.logger.info('HCE-Check-In') do
          "appointments_facility_fetch_failed facility_id=#{facility_id} " \
            "facilities_version=#{facilities_v3_enabled? ? 'v3' : 'v2'} " \
            "error=#{error.class} status=#{error.try(:status)}"
        end
      end
    end
  end
end
