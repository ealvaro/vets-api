# frozen_string_literal: true

require 'common/exceptions'
require 'common/client/errors'
require 'json'

module VAOS
  module V2
    class PatientsService < VAOS::SessionService
      STATSD_KEY_PREFIX = 'api.vaos.patient_eligibility'

      def get_patient_appointment_metadata(clinic_service_id, facility_id, type)
        if Flipper.enabled?(:va_online_scheduling_backend_oh_migration_check, user)
          eligibility_override = check_migration_eligibility_override(facility_id, type)
          return OpenStruct.new(eligibility_override.merge(id: SecureRandom.hex(2))) if eligibility_override
        end

        tags = []
        with_monitoring do
          response = if Flipper.enabled?(:va_online_scheduling_use_vpg, user)
                       tags << 'ehr:cerner'
                       get_patient_appointment_metadata_vpg(clinic_service_id, facility_id, type)
                     else
                       tags << 'ehr:vista'
                       get_patient_appointment_metadata_vaos(clinic_service_id, facility_id, type)
                     end
          if Flipper.enabled?(:va_online_scheduling_metric_tracking_eligibility, user)
            tags += build_tags(response, clinic_service_id, facility_id, type)
            increment_eligibility(response.body&.[](:eligible), tags)
          end
          OpenStruct.new(response.body.merge(id: SecureRandom.hex(2)))
        end
      end

      private

      def get_patient_appointment_metadata_vaos(clinic_service_id, facility_id, type)
        params = {
          clinicalServiceId: clinic_service_id,
          facilityId: facility_id,
          type:
        }

        with_monitoring do
          perform(:get, "/#{base_vaos_route}/patients/#{user.icn}/eligibility", params, headers)
        end
      end

      def get_patient_appointment_metadata_vpg(clinic_service_id, facility_id, type)
        params = {
          clinicalService: clinic_service_id,
          location: facility_id,
          type:
        }

        with_monitoring do
          perform(:get, "/vpg/v1/patients/#{user.icn}/eligibility", params, headers)
        end
      end

      def increment_eligibility(eligibility, tags)
        if eligibility
          StatsD.increment("#{STATSD_KEY_PREFIX}.eligible", tags:)
        else
          StatsD.increment("#{STATSD_KEY_PREFIX}.ineligible", tags:)
        end
      end

      def build_tags(response, clinic_service_id, facility_id, type)
        eligible = response&.body&.[](:eligible)
        type_of_care = clinic_service_id
        scheduling_type = type
        code = response&.body&.[](:ineligibility_reasons)&.[](0)&.[](:coding)&.[](0)&.[](:code)
        display = response&.body&.[](:ineligibility_reasons)&.[](0)&.[](:coding)&.[](0)&.[](:display)

        ["eligible:#{eligible}", "type_of_care:#{type_of_care}", "scheduling_type:#{scheduling_type}",
         "facility_id:#{facility_id}", "ineligibility_reasons_code:#{code}", "ineligibility_reasons_display:#{display}"]
      end

      def check_migration_eligibility_override(facility_id, type)
        migrations = VAOS::OhMigrationsHelper.get_migrations(user:)
        parent_facility_id = facility_id[0, 3]
        if migrations.key?(parent_facility_id) && migrations[parent_facility_id][:disable_eligibility]
          {
            eligible: false,
            ineligibility_reasons: [{
              coding: [
                {
                  code: type == 'direct' ? 'facility-cs-direct-disabled' : 'facility-cs-request-disabled',
                  display: 'OH migration'
                }
              ]
            }]
          }
        end
      end
    end
  end
end
