# frozen_string_literal: true

module VAOS
  module V2
    class ClinicsController < VAOS::BaseController
      CLINIC_KEY = 'Clinic'

      def index
        response = systems_service.get_facility_clinics(location_id:,
                                                        clinic_ids: params[:clinic_ids],
                                                        clinical_service: params[:clinical_service],
                                                        page_size: params[:page_size],
                                                        page_number: params[:page_number])
        render json: VAOS::V2::ClinicsSerializer.new(response)
      end

      private

      def filter_type_of_care_facilities(facilities)
        # Return facilities without filtering if no service id is provided
        service_id = params[:clinical_service_id]
        return facilities unless service_id

        # Retrieve facility scheduling configurations
        facility_ids = facilities.pluck(:id).to_csv(row_sep: nil)
        configurations = mobile_facility_service.get_scheduling_configurations(facility_ids)&.[](:data)
        supported_facilities = []

        facilities.each do |facility|
          # Include facility in results if direct schedule or request is enabled for the given service
          configuration = configurations&.find { |config| config[:facility_id] == facility[:id] }
          service_configuration = configuration&.[](:services)&.find { |service| service[:id] == service_id }
          if service_configuration&.dig(:direct, :enabled) || service_configuration&.dig(:request, :enabled)
            supported_facilities.push(facility)
          end
        end

        log_no_supported_facilities(service_id) if supported_facilities.blank?

        supported_facilities
      end

      def log_no_supported_facilities(service_id)
        Rails.logger.info('VAOS recent_facilities', "No facility supporting #{service_id} service was found.")
      end

      def systems_service
        VAOS::V2::SystemsService.new(current_user)
      end

      def mobile_facility_service
        @mobile_facility_service ||=
          VAOS::V2::MobileFacilityService.new(current_user)
      end

      def location_id
        params.require(:location_id)
      end
    end
  end
end
