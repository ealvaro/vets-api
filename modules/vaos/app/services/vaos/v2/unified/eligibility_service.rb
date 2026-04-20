# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class EligibilityService
        STATSD_KEY_PREFIX = 'api.vaos.unified_eligibility'

        attr_reader :current_user

        def initialize(current_user)
          @current_user = current_user
        end

        ##
        # Checks whether the patient is eligible for direct scheduling at a VA
        # facility for the given VAOS clinical service.
        #
        # NOTE: Callers must pass an already-mapped VAOS service type
        # (e.g. +'primaryCare'+, +'foodAndNutrition'+, +'clinicalPharmacyPrimaryCare'+),
        # NOT a raw CCRA +category_of_care+ string and NOT a Lighthouse
        # +serviceId+. The mapping happens upstream in
        # {VAOS::V2::Unified::CcraCategoryMapper}; mapping a second time here
        # would fail for VAOS-only identifiers (e.g. +'foodAndNutrition'+ is
        # not a key in +ServiceTypeMapper::LIGHTHOUSE_TO_VAOS+) and silently
        # mark every facility ineligible.
        #
        # @param facility_id [String] VA facility identifier (Lighthouse +unique_id+, same as VAOS location)
        # @param vaos_service_type [String] VAOS clinical service type
        # @return [Hash] with :facility_id, :vaos_service_type, and :direct_eligible
        #
        def check_eligibility(facility_id:, vaos_service_type:)
          if vaos_service_type.blank?
            StatsD.increment("#{STATSD_KEY_PREFIX}.unmappable_service_type")
            return ineligible_result(facility_id)
          end

          direct_eligible = eligible?(vaos_service_type, facility_id, 'direct')
          # Request eligibility disabled for pilot — can take >10s for non-Judy users
          # request_eligible = eligible?(vaos_service_type, facility_id, 'request')
          StatsD.increment("#{STATSD_KEY_PREFIX}.success")

          {
            facility_id:,
            vaos_service_type:,
            direct_eligible:
          }
        end

        private

        def ineligible_result(facility_id)
          { facility_id:, vaos_service_type: nil, direct_eligible: false }
        end

        def eligible?(clinical_service_id, facility_id, type)
          result = patients_service.get_patient_appointment_metadata(clinical_service_id, facility_id, type)
          result&.eligible == true
        rescue => e
          log_error('eligibility_check_failed',
                    clinical_service_id:, facility_id:, type:, error: e.message)
          StatsD.increment("#{STATSD_KEY_PREFIX}.eligibility.failure")
          false
        end

        def patients_service
          @patients_service ||= VAOS::V2::PatientsService.new(current_user)
        end

        def log_error(event, **context)
          Rails.logger.error("#{STATSD_KEY_PREFIX}.#{event}", context)
        end
      end
    end
  end
end
