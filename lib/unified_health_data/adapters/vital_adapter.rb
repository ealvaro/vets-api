# frozen_string_literal: true

require 'medical_records/medical_records_log'
require_relative '../constants'
require_relative '../models/vital'
require_relative 'date_time_helpers'

module UnifiedHealthData
  module Adapters
    class VitalAdapter
      include UnifiedHealthData::Constants
      include DateTimeHelpers

      FILTERED_STATUSES = %w[entered-in-error].freeze

      def initialize(user: nil)
        @mr_log = MedicalRecords::MedicalRecordsLog.new(user:)
      end

      def parse(records)
        return [] if records.blank?

        filtered = records.select do |record|
          resource = record['resource']
          next false unless resource && resource['resourceType'] == 'Observation'

          unless FILTERED_STATUSES.exclude?(resource['status'])
            log_filtered_vital(resource)
            next false
          end

          # Filter out Oracle Health "weight dosing" records - these are auto-generated
          # duplicates of "weight measured" and should not be displayed to Veterans
          if weight_dosing?(resource)
            log_filtered_weight_dosing(resource)
            next false
          end

          true
        end
        parsed = filtered.map { |record| parse_single_vital(record) }
        log_locations_found
        parsed.compact
      end

      def parse_single_vital(record)
        return nil if record.nil? || record['resource'].nil?

        resource = record['resource']
        record_type = get_type(resource)
        date_value = resource['effectiveDateTime'] || nil

        UnifiedHealthData::Vital.new(
          id: resource['id'],
          name: get_name(resource),
          type: record_type,
          date: date_value,
          sort_date: normalize_date_for_sorting(date_value),
          measurement: get_measurements(resource, record_type),
          location: extract_location(resource),
          notes: extract_notes(resource)
        )
      end

      private

      def location_tracking_array
        @location_tracking_array ||= []
      end

      def log_locations_found
        unless location_tracking_array.empty?
          # Log how many vital records had multiple locations
          # Log only the unique location sets found (and the count) to reduce log noise
          Rails.logger.info(
            message: "Multiple locations found for #{location_tracking_array.size} Vital records:",
            locations: location_tracking_array.uniq,
            service: 'unified_health_data'
          )
        end
      end

      def get_name(resource)
        resource.dig('code', 'text')&.humanize || resource.dig('code', 'coding', 0, 'display')&.humanize || ''
      end

      def get_type(record)
        VITAL_LOINC_CODES.each do |key, value|
          return value if record['code']['coding']&.any? { |coding| coding['code'] == key }
        end
        # If we reach here, no matching LOINC codes were found, log them and return 'OTHER'
        coding_info = record['code']['coding']&.map do |coding|
          "code: #{coding['code']}, display: #{coding['display'] || ''}" if coding['code']
        end
        Rails.logger.warn("Unknown LOINC codes for Vital record text: #{record['code']['text']}, #{coding_info}")
        'OTHER'
      end

      def array_and_has_items(item)
        item.is_a?(Array) && !item.empty?
      end

      def extract_notes(resource)
        return [] unless resource['note']

        if array_and_has_items(resource['note'])
          resource['note'].map { |note| note['text'] }.compact
        else
          [resource['note']['text']].compact
        end
      end

      def get_measurements(record, record_type)
        # Specific to both VistA + OH blood pressure Diastolic & Systolic records
        if array_and_has_items(record['component'])
          format_blood_pressure(record)
        # Specific to items with multiple units of measure, e.g. Weight in both kg and lbs
        elsif record['valueQuantity'].is_a?(Hash) && array_and_has_items(record['valueQuantity']['extension'])
          format_extension_measurements(record, record_type)
        else
          units = VITAL_UNIT_DISPLAY_TEXT[record_type.to_sym] || ''
          if record_type == 'HEIGHT'
            format_height(record)
          else
            value = record.dig('valueQuantity', 'value')
            value ? "#{value}#{units}" : nil
          end
        end
      rescue
        nil
      end

      # TODO: how to handle if multiple locations?
      def extract_location(record)
        # VistA - location is in the performer.extension array
        # OH also has a performer.extension array but the "performer" is the practitioner
        # Both OH + VistA - location is in the contained array, might be multiple listed,
        # OH has no definitive reference, unlike VistA
        if array_and_has_items(record['contained'])
          # For now just get the first one
          # Prefer managingOrganization.display for Location resources (stable facility name)
          location_array = record['contained'].map do |res|
            next nil unless res['resourceType'] == FHIR_RESOURCE_TYPES[:LOCATION]

            res.dig('managingOrganization', 'display') || res['name']
          end.compact
          if location_array.size > 1
            locations = { 'locations found' => location_array.size, 'names' => location_array.join('; ') }
            location_tracking_array.push(locations)
          end
          location_array.first unless location_array.empty?
        end
      rescue
        nil
      end

      def format_blood_pressure(record)
        systolic_ref = nil
        diastolic_ref = nil
        record['component'].each do |item|
          if item['code']['coding']&.any? { |coding| coding['code'] == '8480-6' }
            systolic_ref = item
          elsif item['code']['coding']&.any? { |coding| coding['code'] == '8462-4' }
            diastolic_ref = item
          end
        end

        if systolic_ref && diastolic_ref
          systolic_value = systolic_ref.dig('valueQuantity', 'value')
          diastolic_value = diastolic_ref.dig('valueQuantity', 'value')
          "#{systolic_value}/#{diastolic_value}" if systolic_value && diastolic_value
        end
      end

      def format_height(height_ref)
        value = height_ref.dig('valueQuantity', 'value')
        return nil unless value

        ft_in = value.divmod(12)
        "#{ft_in[0]}#{VITAL_UNIT_DISPLAY_TEXT[:HEIGHT_FT]}, #{ft_in[1].round(1)}#{VITAL_UNIT_DISPLAY_TEXT[:HEIGHT_IN]}"
      end

      def format_extension_measurements(record, record_type)
        extensions = record['valueQuantity']['extension']
        case record_type
        when 'HEIGHT'
          height_ref = extensions.find { |ext| ext.dig('valueQuantity', 'code') == '[in_i]' }
          return nil unless height_ref

          format_height(height_ref)
        when 'WEIGHT'
          format_extension_value(extensions, '[lb_av]', VITAL_UNIT_DISPLAY_TEXT[:WEIGHT])
        when 'TEMPERATURE'
          format_extension_value(extensions, '[degF]', VITAL_UNIT_DISPLAY_TEXT[:TEMPERATURE])
        # if other types with multiple entries, but not specifically differentiated, return the default valueQuantity
        else
          value = record.dig('valueQuantity', 'value')
          return nil unless value

          "#{value}#{VITAL_UNIT_DISPLAY_TEXT[record_type.to_sym] || ''}"
        end
      end

      def format_extension_value(extensions, code, units)
        ref = extensions.find { |ext| ext.dig('valueQuantity', 'code') == code }
        return nil unless ref

        value = ref.dig('valueQuantity', 'value')
        return nil unless value

        "#{value}#{units}"
      end

      def find_contained(record, reference, type = nil)
        return nil unless reference && record['contained']

        if reference.start_with?('#')
          # Reference is in the format #mhv-resourceType-id
          target_id = reference.delete_prefix('#')
          resource = record['contained'].detect { |res| res['id'] == target_id }
          return nil unless resource && resource['resourceType'] == type
        else
          # Reference is in the format ResourceType/id
          type_id = reference.split('/')
          resource = record['contained'].detect { |res| res['id'] == type_id.last }
          return nil unless resource && (resource['resourceType'] == type_id.first || resource['resourceType'] == type)
        end
        resource
      end

      def log_filtered_vital(resource)
        @mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::VITALS,
          action: 'filter',
          record_id: resource['id'],
          status: resource['status'],
          reason: 'entered_in_error'
        )

        StatsD.increment('unified_health_data.vital.filtered_observation',
                         tags: ['reason:entered_in_error'])
      end

      def weight_dosing?(resource)
        resource.dig('code', 'text')&.downcase == 'weight dosing'
      end

      def log_filtered_weight_dosing(resource)
        @mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::VITALS,
          action: 'filter',
          record_id: resource['id'],
          reason: 'weight_dosing'
        )

        StatsD.increment('unified_health_data.vital.filtered_observation',
                         tags: ['reason:weight_dosing'])
      end
    end
  end
end
