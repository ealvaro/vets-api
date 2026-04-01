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
        # Checks patient eligibility for a specific service type at a VA facility
        # selected from the unified provider list. Maps the referral's category of care
        # from Lighthouse format to VAOS format, then checks whether the patient is
        # eligible for direct scheduling.
        #
        # @param va_provider [VAOS::V2::Unified::VAProvider] selected VA facility from provider search
        # @param category_of_care [String] Lighthouse service type from the referral (e.g., 'primaryCare')
        # @return [Hash] with :facility_id, :vaos_service_type, and :direct_eligible
        #
        def check_eligibility(va_provider, category_of_care)
          facility_id = va_provider.location_id
          vaos_service_type = ServiceTypeMapper.to_vaos(category_of_care)

          if vaos_service_type.nil?
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
