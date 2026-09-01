# frozen_string_literal: true

module VAOS
  module V2
    class SystemsService < VAOS::SessionService
      def get_facility_clinics(location_id:,
                               clinical_service: nil,
                               clinic_ids: nil,
                               page_size: nil,
                               page_number: nil)
        with_monitoring do
          response = get_clinics(location_id:, clinical_service:, clinic_ids:, page_size:, page_number:)
          clinics = response.body[:data]

          # When specific clinic ids are requested, skip the patient direct scheduling filter.
          if clinic_ids.blank?
            clinics = filter_clinics_by_patient_direct_scheduling(clinics, location_id:, clinical_service:)
          end

          clinics.map { |clinic| OpenStruct.new(clinic) }
        end
      end

      def get_available_slots(options = {})
        location_id = options[:location_id]
        clinic_id = options[:clinic_id]
        clinical_service = options[:clinical_service]
        provider_id = options[:provider_id]
        start_dt = options[:start_dt]
        end_dt = options[:end_dt]

        with_monitoring do
          response = if Flipper.enabled?(:va_online_scheduling_use_vpg, user)
                       get_slots_vpg(location_id:, clinic_id:, clinical_service:, provider_id:, start_dt:, end_dt:)
                     else
                       get_slots_vaos(location_id:, clinic_id:, start_dt:, end_dt:)
                     end

          response.body[:data] ? response.body[:data].map { |slot| OpenStruct.new(slot) } : []
        end
      end

      def get_next_available_slots(options = {})
        location_id = options[:location_id]
        clinic_ids = options[:clinic_ids]
        on_or_after = options[:on_or_after]
        before = options[:before]

        with_monitoring do
          response = get_next_available_slots_vpg(
            location_id:,
            clinic_ids:,
            on_or_after:,
            before:
          )

          build_next_available_slots(response.body)
        end
      end

      private

      # Clinics not enabled for patient direct scheduling should never be displayed for self-scheduling.
      def filter_clinics_by_patient_direct_scheduling(clinics, location_id:, clinical_service:)
        schedulable, unschedulable = clinics.partition { |clinic| clinic[:patient_direct_scheduling] }

        if unschedulable.any?
          filtered_clinics = unschedulable.map do |clinic|
            { id: clinic[:id], patient_direct_scheduling: clinic[:patient_direct_scheduling] }
          end

          Rails.logger.info(
            'VAOS::V2::SystemsService#get_facility_clinics, clinics filtered out due to patient_direct_scheduling',
            { location_id:, clinical_service:, filtered_clinics: }
          )
        end

        schedulable
      end

      def get_clinics(location_id:, clinical_service:, clinic_ids:, page_size:, page_number:)
        page_size = 0 if page_size.nil? # 0 is the default for the VAOS service which means return all clinics
        url = if Flipper.enabled?(:va_online_scheduling_use_vpg, user)
                "/vpg/v1/locations/#{location_id}/clinics"
              else
                "/#{base_vaos_route}/locations/#{location_id}/clinics"
              end

        url_params = {
          'patientIcn' => get_icn(clinical_service),
          'clinicIds' => get_clinic_ids(clinic_ids),
          'clinicalService' => clinical_service,
          'pageSize' => page_size,
          'pageNumber' => page_number
        }.compact

        #  'clinicalService' is used when retrieving clinics for appointment scheduling,
        #  triggering stop code filtering to avoid displaying unavailable clinics.
        url_params.merge!('enableStopCodeFilter' => true) if url_params['clinicalService'].present?

        # splitting upstream service call into separately monitored methods for metric tracking
        if Flipper.enabled?(:va_online_scheduling_use_vpg, user)
          perform_get_clinics_request_vpg(url, url_params)
        else
          perform_get_clinics_request_vaos(url, url_params)
        end
      end

      def perform_get_clinics_request_vpg(url, url_params)
        with_monitoring do
          perform(:get, url, url_params, headers)
        end
      end

      def perform_get_clinics_request_vaos(url, url_params)
        with_monitoring do
          perform(:get, url, url_params, headers)
        end
      end

      # Patient icn is only valid if the clinical service is of type primary care.
      def get_icn(clinical_service)
        clinical_service == 'primaryCare' ? user.icn : nil
      end

      # Depending on how the clinic ids array query parameter is passed in rails can see it
      # internally as an array or a comma separated string. VAOS Service will only accept a
      # CSV string of clinic ids. This method will convert the clinic ids to a csv string if not
      # one already.
      def get_clinic_ids(ids)
        ids.is_a?(Array) ? ids.to_csv(row_sep: nil) : ids
      end

      def get_clinic_list(ids)
        ids.is_a?(Array) ? ids : ids.to_s.split(',')
      end

      def get_slots_vaos(location_id:, clinic_id:, start_dt:, end_dt:)
        url_path = "/#{base_vaos_route}/locations/#{location_id}/clinics/#{clinic_id}/slots"
        url_params = {
          'start' => start_dt,
          'end' => end_dt
        }
        with_monitoring do
          perform(:get, url_path, url_params, headers)
        end
      end

      def get_slots_vpg(options = {})
        url_path = '/vpg/v1/slots'
        url_params = {
          'start' => options[:start_dt],
          'end' => options[:end_dt],
          'clinic' => options[:clinic_id],
          'clinicalService' => options[:clinical_service],
          'location' => options[:location_id],
          'provider' => options[:provider_id]
        }.compact

        with_monitoring do
          perform(:get, url_path, url_params, headers)
        end
      end

      def get_next_available_slots_vpg(location_id:, clinic_ids:, before:, on_or_after: nil)
        url_path = '/vpg/v1/next-available-slot'
        url_params = {
          'site' => location_id,
          'clinic' => get_clinic_ids(clinic_ids),
          'before' => before,
          'onOrAfter' => on_or_after
        }.compact

        with_monitoring do
          perform(:get, url_path, url_params, headers)
        end
      end

      def build_next_available_slots(body)
        Array(body[:data] || body['data']).map do |slot|
          clinic_id = slot[:ien] || slot['ien']

          OpenStruct.new(
            id: clinic_id,
            clinic_id:,
            status: slot[:status] || slot['status'],
            has_availability: extract_has_availability(slot),
            slot_id: extract_slot_id(slot),
            start: slot[:start] || slot['start'],
            end: slot[:end] || slot['end']
          )
        end
      end

      def extract_has_availability(slot)
        slot[:has_availability] ||
          slot['has_availability'] ||
          slot[:hasAvailability] ||
          slot['hasAvailability']
      end

      def extract_slot_id(slot)
        slot[:slot_id] ||
          slot['slot_id'] ||
          slot[:slotId] ||
          slot['slotId']
      end
    end
  end
end
