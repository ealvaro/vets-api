# frozen_string_literal: true

require 'common/exceptions'
require 'common/client/errors'
require 'json'
require 'memoist'

module CheckIn
  module VAOS
    class FacilityService < Common::Client::Base
      include Common::Client::Concerns::Monitoring

      STATSD_KEY_PREFIX = 'api.check_in.vaos.facilities'

      def get_facility_with_cache(facility_id:)
        Rails.cache.fetch(facility_cache_key(facility_id), expires_in: 12.hours) do
          get_facility(facility_id:)
        rescue Common::Exceptions::BackendServiceException, Breakers::OutageException => e
          # Enrichment is best-effort: a facility lookup failure must not take down the appointments
          # response, which has already been fetched successfully. Cache the miss so other
          # appointments at the same facility don't re-hit (and trip the circuit breaker on) a
          # known-bad upstream within the same response.
          record_enrichment_failure(kind: 'facility', facility_id:, error: e,
                                    metric: CheckIn::Constants::STATSD_FACILITY_ENRICHMENT_FAILED)
        end
      end

      def get_facility(facility_id:)
        with_monitoring do
          response = perform(:get, facilities_url(facility_id:), {}, headers)
          Oj.load(response.body).with_indifferent_access
        end
      end

      def track_vds_clinics_skipped_flag_off!
        return unless facilities_v3_enabled? && !vds_site_info_clinics_enabled?

        StatsD.increment(CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_SKIPPED_FLAG_OFF)
        Rails.logger.info('HCE-Check-In') do
          'appointments_vds_clinics_skipped_flag_off facilities_v3_enabled=true vds_site_info_clinics_enabled=false'
        end
      end

      def get_clinic_with_cache(facility_id:, clinic_id:, facility: nil)
        if facilities_v3_enabled?
          return nil unless vds_site_info_clinics_enabled?

          site_id = vista_site_for_vds_clinics(facility:, location_id: facility_id, clinic_id:)
          return nil unless site_id

          clinics = Rails.cache.fetch(vds_site_clinics_cache_key(site_id), expires_in: 12.hours) do
            vds_site_info_clinics_service.get_clinics(site_id:)
          rescue Common::Exceptions::BackendServiceException, Breakers::OutageException => e
            # Best-effort enrichment: e.g. a non-VistA (Oracle Health) site_id sent to the VDS
            # site-info endpoint returns a 400. Cache the miss and degrade to nil so the appointment
            # is still returned without clinic info.
            record_enrichment_failure(kind: 'clinic', facility_id:, clinic_id:, error: e,
                                      metric: CheckIn::Constants::STATSD_CLINIC_ENRICHMENT_FAILED)
          end
          return nil if clinics.nil?

          clinic_from_vds_list(clinics, clinic_id, site_id:)
        else
          Rails.cache.fetch("check_in.vaos_clinic_#{facility_id}_#{clinic_id}", expires_in: 12.hours) do
            get_clinic(facility_id:, clinic_id:, facility:)
          rescue Common::Exceptions::BackendServiceException, Breakers::OutageException => e
            record_enrichment_failure(kind: 'clinic', facility_id:, clinic_id:, error: e,
                                      metric: CheckIn::Constants::STATSD_CLINIC_ENRICHMENT_FAILED)
          end
        end
      end

      def get_clinic(facility_id:, clinic_id:, facility: nil)
        if facilities_v3_enabled?
          return nil unless vds_site_info_clinics_enabled?

          site_id = vista_site_for_vds_clinics(facility:, location_id: facility_id, clinic_id:)
          return nil unless site_id

          clinics = vds_site_info_clinics_service.get_clinics(site_id:)
          clinic_from_vds_list(clinics, clinic_id, site_id:)
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

      def log_vds_clinic_vista_site_missing(location_id:, clinic_id:)
        StatsD.increment(CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_VISTA_SITE_MISSING)
        Rails.logger.info('HCE-Check-In') do
          "appointments_vds_clinic_vista_site_missing location_id=#{location_id} clinic_id=#{clinic_id}"
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

      # VDS-Site-Info lists clinics by VistA site id from MFS v3 facility enrichment. VAOS locationId
      # may be an institution id (e.g. 983GC); do not pass it to VDS when vistaSite is unavailable.
      def vista_site_for_vds_clinics(facility:, location_id:, clinic_id:)
        site_id = facility&.with_indifferent_access&.dig(:vistaSite).presence
        return site_id if site_id

        log_vds_clinic_vista_site_missing(location_id:, clinic_id:)
        nil
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

      # Logs the skip with enough context to triage, increments the metric, and returns nil so the
      # cache stores the miss. No PII: only station/clinic identifiers and upstream error metadata.
      def record_enrichment_failure(kind:, facility_id:, error:, metric:, clinic_id: nil)
        Rails.logger.info('HCE-Check-In') { enrichment_failure_log(kind:, facility_id:, clinic_id:, error:) }
        StatsD.increment(metric)
        nil
      end

      def enrichment_failure_log(kind:, facility_id:, error:, clinic_id: nil)
        parts = ["appointments_#{kind}_enrichment_skipped", "facility_id=#{facility_id}"]
        parts << "clinic_id=#{clinic_id}" if clinic_id
        parts << "facilities_version=#{facilities_v3_enabled? ? 'v3' : 'v2'}"
        parts << "vds_clinics=#{vds_site_info_clinics_enabled? ? 'enabled' : 'disabled'}" if kind == 'clinic'
        parts << "error=#{error.class}"
        parts << "code=#{error.try(:key)}"
        parts << "status=#{error.try(:original_status)}"
        parts << "likely_cause=#{enrichment_failure_cause(kind, error)}"
        parts.join(' ')
      end

      # Best-effort heuristic to point on-call at the probable root cause. VDS site-info and MFS
      # only serve VistA sites, so a 400 most often means a non-VistA (e.g. Oracle Health) or
      # otherwise unrecognized identifier was sent upstream.
      def enrichment_failure_cause(kind, error)
        return 'upstream_circuit_breaker_open' if error.is_a?(Breakers::OutageException)

        case error.try(:original_status)
        when 400
          kind == 'clinic' ? 'non_vista_site_or_unknown_clinic' : 'unrecognized_or_non_vista_facility'
        when 404 then 'identifier_not_found_upstream'
        when 500..599 then 'upstream_server_error'
        else 'unknown'
        end
      end
    end
  end
end
