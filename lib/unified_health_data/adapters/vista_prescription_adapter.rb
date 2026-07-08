# frozen_string_literal: true

require_relative 'renewal_window'

module UnifiedHealthData
  module Adapters
    class VistaPrescriptionAdapter
      include RenewalWindow
      # Parses a VistA medication record into a UnifiedHealthData::Prescription
      #
      # @param medication [Hash] Raw medication data from VistA
      # @return [UnifiedHealthData::Prescription, nil] Parsed prescription or nil if invalid
      def parse(medication)
        return nil if medication.nil? || medication['prescriptionId'].nil?

        UnifiedHealthData::Prescription.new(build_prescription_attributes(medication))
      rescue => e
        Rails.logger.error("Error parsing VistA prescription: #{e.message}")
        nil
      end

      private

      def build_prescription_attributes(medication)
        tracking_data = build_tracking_information(medication)
        dispenses_data = build_dispenses_information(medication)

        build_core_attributes(medication)
          .merge(build_tracking_attributes(tracking_data, medication))
          .merge(build_contact_and_source_attributes(medication))
          .merge(dispenses: dispenses_data)
          .merge(sorted_dispensed_date: extract_sorted_dispensed_date(medication, dispenses_data))
          .merge(source_ehr: UnifiedHealthData::Prescription::SOURCE_EHR_VISTA)
      end

      def build_core_attributes(medication)
        {
          id: medication['prescriptionId'].to_s,
          type: 'Prescription',
          refill_status: medication['refillStatus'],
          refill_submit_date: convert_to_iso8601(medication['refillSubmitDate'], field_name: 'refill_submit_date'),
          refill_date: convert_to_iso8601(medication['refillDate'], field_name: 'refill_date'),
          refill_remaining: medication['refillRemaining'],
          facility_name: medication['facilityApiName'].presence || medication['facilityName'],
          ordered_date: convert_to_iso8601(medication['orderedDate'], field_name: 'ordered_date'),
          quantity: medication['quantity'],
          expiration_date: normalize_expiration_date(medication['expirationDate']),
          prescription_number: medication['prescriptionNumber'],
          prescription_name: medication['prescriptionName'].presence || medication['orderableItem'],
          dispensed_date: convert_to_iso8601(medication['dispensedDate'], field_name: 'dispensed_date'),
          station_number: medication['stationNumber'],
          is_refillable: medication['isRefillable'],
          is_renewable: extract_is_renewable(medication),
          is_renewal_flow_enabled: false,
          cmop_ndc_number: medication['cmopNdcNumber']
        }
      end

      def build_tracking_attributes(tracking_data, medication)
        {
          is_trackable: medication['isTrackable'] || false,
          tracking: tracking_data
        }
      end

      def build_contact_and_source_attributes(medication)
        {
          instructions: medication['sig'],
          facility_phone_number: medication['cmopDivisionPhone'],
          cmop_division_phone: medication['cmopDivisionPhone'],
          prescription_source: medication['prescriptionSource'],
          disclaimer: medication['disclaimer'],
          provider_name: build_provider_name(medication),
          dial_cmop_division_phone: medication['dialCmopDivisionPhone'],
          indication_for_use: medication['indicationForUse'],
          remarks: medication['remarks'],
          disp_status: medication['dispStatus']
        }
      end

      def build_tracking_information(medication)
        extract_tracking_array(medication).map do |tracking|
          {
            prescription_name: medication['prescriptionName'],
            prescription_number: medication['prescriptionNumber'],
            ndc_number: tracking['ndc'] || medication['ndc'],
            prescription_id: medication['prescriptionId'],
            tracking_number: tracking['trackingNumber'],
            complete_date_time: format_shipped_date(tracking['completeDateTime']),
            carrier: tracking['carrier'],
            others_in_same_package: tracking['othersInSamePackage'] || false
          }
        end
      end

      # Extracts the tracking array from the medication.
      # Format: trackingList is a Hash with a 'tracking' array.
      def extract_tracking_array(medication)
        tracking_list = medication['trackingList']
        return [] unless tracking_list.is_a?(Hash)

        entries = tracking_list['tracking']
        entries.is_a?(Array) ? entries : []
      end

      def format_shipped_date(date_string)
        convert_to_iso8601(date_string, field_name: 'shipped_date')
      end

      def build_dispenses_information(medication)
        rf_records = medication.dig('rxRFRecords', 'rfRecord') || []
        return [] unless rf_records.is_a?(Array)

        rf_records.filter_map do |record|
          next unless record.is_a?(Hash)

          build_dispense_attributes(record)
        end
      end

      def build_dispense_attributes(record)
        {
          status: record['refillStatus'],
          dispensed_date: convert_to_iso8601(record['dispensedDate'], field_name: 'dispensed_date'),
          refill_date: convert_to_iso8601(record['refillDate'], field_name: 'refill_date'),
          facility_name: record['facilityApiName'].presence || record['facilityName'],
          instructions: record['sig'],
          quantity: record['quantity'],
          prescription_name: record['prescriptionName'],
          id: record['id'],
          refill_submit_date: convert_to_iso8601(record['refillSubmitDate'], field_name: 'refill_submit_date'),
          prescription_number: record['prescriptionNumber'],
          cmop_division_phone: record['cmopDivisionPhone'],
          cmop_ndc_number: record['cmopNdcNumber'],
          remarks: record['remarks'],
          dial_cmop_division_phone: record['dialCmopDivisionPhone'],
          disclaimer: record['disclaimer']
        }
      end

      def convert_to_iso8601(date_string, field_name:)
        return nil if date_string.blank?

        Time.parse(date_string.to_s).utc.iso8601(3)
      rescue ArgumentError => e
        Rails.logger.warn("Failed to parse #{field_name} '#{date_string}': #{e.message}")
        date_string
      end

      # Returns the most recent dispensed date across all refill records,
      # falling back to the top-level dispensed_date.
      # Uses safe date coercion so one bad date string doesn't drop the entire prescription.
      def extract_sorted_dispensed_date(medication, dispenses_data)
        dates = dispenses_data.filter_map do |d|
          d[:dispensed_date]&.to_date
        rescue ArgumentError, TypeError
          nil
        end
        max_date = dates.max
        return max_date.to_s if max_date

        raw = medication['dispensedDate']
        return nil if raw.blank?

        convert_to_iso8601(raw, field_name: 'dispensed_date')&.to_date&.to_s
      rescue ArgumentError, TypeError
        nil
      end

      # Normalizes VistA expiration dates to noon UTC of the intended calendar date.
      # VistA dates include timezone (EDT/EST), so we parse to extract the local date,
      # then return noon UTC. This prevents off-by-one display errors in western timezones.
      #
      # @param date_string [String] VistA date string, e.g. "Wed, 15 Jul 2026 00:00:00 EDT"
      # @return [String, nil] ISO 8601 noon UTC string, e.g. "2026-07-15T12:00:00.000Z"
      def normalize_expiration_date(date_string)
        return nil if date_string.blank?

        # Time.parse handles RFC 2822 timezone abbreviations (EDT, EST, etc.)
        # Time.zone.parse would ignore these abbreviations, giving wrong results.
        parsed = Time.parse(date_string.to_s) # rubocop:disable Rails/TimeZone
        local_date = parsed.to_date
        Time.utc(local_date.year, local_date.month, local_date.day, 12, 0, 0).iso8601(3)
      rescue ArgumentError => e
        Rails.logger.warn("Failed to normalize expiration date '#{date_string}': #{e.message}")
        nil
      end

      def build_provider_name(medication)
        last_name = medication['providerLastName']
        first_name = medication['providerFirstName']

        return nil if last_name.blank? && first_name.blank?

        [last_name, first_name].compact.join(', ')
      end

      # Computes renewability per spec instead of trusting upstream isRenewable.
      # A VistA prescription is renewable if it is a VA prescription AND:
      #   - Active with zero refills remaining, OR
      #   - Expired within the last 120 days
      def extract_is_renewable(medication)
        return false if medication['prescriptionSource'] == 'NV'

        disp_status = medication['dispStatus']

        refill_remaining = medication['refillRemaining']
        return true if disp_status == 'Active' && !refill_remaining.nil? && refill_remaining.to_i.zero?

        if disp_status == 'Expired'
          expiration_time = parse_expiration_time(medication['expirationDate'])
          return true if expiration_time.present? && within_renewal_window_days?(expiration_time)
        end

        false
      end

      def parse_expiration_time(date_string)
        return nil if date_string.blank?

        # Time.parse handles RFC 2822 timezone abbreviations (EDT, EST, etc.)
        # Time.zone.parse would ignore these, causing incorrect renewability calculations.
        Time.parse(date_string.to_s).in_time_zone
      rescue ArgumentError
        nil
      end
    end
  end
end
