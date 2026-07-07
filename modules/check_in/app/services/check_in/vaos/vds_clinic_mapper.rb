# frozen_string_literal: true

module CheckIn
  module VAOS
    # Maps VDS-Site-Info clinic list items to the MFS v2 single-clinic { data: ... } shape
    # expected by AppointmentSerializer (VDSv2 Migration Guide: MFS serviceName -> VDS name).
    class VdsClinicMapper
      def self.find_by_clinic_ien(clinics, clinic_id)
        return nil if clinics.blank?

        clinics.find { |clinic| clinic_indifferent(clinic)[:clinicIen].to_s == clinic_id.to_s }
      end

      def self.to_clinic_info(vds_clinic)
        clinic = clinic_indifferent(vds_clinic)

        {
          data: {
            clinicId: clinic[:clinicIen],
            serviceName: clinic[:name],
            friendlyName: friendly_name(clinic),
            physicalLocation: clinic[:physicalLocation]
          }
        }.with_indifferent_access
      end

      def self.friendly_name(clinic)
        # VDS-Site-Info migration guide documents friendlyName; production may still send
        # patientFriendlyName until upstream fully migrates.
        clinic[:friendlyName].presence || clinic[:patientFriendlyName].presence
      end
      private_class_method :friendly_name

      def self.clinic_indifferent(clinic)
        clinic.with_indifferent_access
      end
      private_class_method :clinic_indifferent
    end
  end
end
