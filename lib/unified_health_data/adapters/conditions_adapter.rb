# frozen_string_literal: true

require 'medical_records/medical_records_log'
require_relative '../models/condition'
require_relative 'date_time_helpers'
require_relative 'station_helpers'

module UnifiedHealthData
  module Adapters
    class ConditionsAdapter
      include DateTimeHelpers
      include StationHelpers

      def initialize(user: nil)
        @mr_log = MedicalRecords::MedicalRecordsLog.new(user:)
      end

      def parse(records, filter_by_status: true)
        return [] if records.blank?

        filtered = records.select do |record|
          resource = record['resource']
          next false unless resource && resource['resourceType'] == 'Condition'
          next true unless filter_by_status

          unless should_include_condition?(resource)
            log_filtered_condition(resource)
            next false
          end
          true
        end
        parsed = filtered.map { |record| parse_single_condition(record, filter_by_status:) }
        parsed.compact
      end

      def parse_single_condition(record, filter_by_status: true)
        return nil if record.nil? || record['resource'].nil?

        resource = record['resource']

        # Filter out conditions without active clinical status if filtering is enabled
        return nil if filter_by_status && !should_include_condition?(resource)

        date_value, facility_tz = resolve_date_and_timezone(resource)

        UnifiedHealthData::Condition.new(
          id: resource['id'],
          date: date_value,
          sort_date: normalize_date_for_sorting(date_value),
          name: resource.dig('code', 'coding', 0, 'display') || resource.dig('code', 'text') || '',
          provider: extract_condition_provider(resource),
          facility: extract_condition_facility(resource),
          comments: extract_condition_comments(resource),
          facility_timezone: facility_tz
        )
      end

      private

      # Attribute timezone conversion errors to the conditions domain rather than
      # the DateTimeHelpers default (LABS), so Datadog logs are labeled correctly.
      def timezone_conversion_log_resource
        MedicalRecords::MedicalRecordsLog::CONDITIONS
      end

      # Dual-path logging: structured mr_log when available, Rails.logger fallback otherwise.
      # Required by DateTimeHelpers#log_timezone_conversion_error.
      def log_adapter(level, structured_opts, fallback_message, fallback_opts = {})
        if @mr_log
          @mr_log.public_send(level, **structured_opts)
        else
          Rails.logger.public_send(level, fallback_message, fallback_opts.presence)
        end
      end

      # Resolves the date and facility timezone for a condition.
      # Year-only and date-only values are passed through without conversion,
      # since converting them would shift the date incorrectly.
      # Full datetime values are converted to facility local time when a station
      # number can be extracted from the contained resources.
      #
      # @param resource [Hash] FHIR Condition resource
      # @return [Array(String, String)] [converted_date, facility_timezone] or [raw_date, nil]
      def resolve_date_and_timezone(resource)
        raw_date = resource['recordedDate'].presence
        if raw_date.blank?
          raw_date = resource['onsetDateTime'].presence
          StatsD.increment('unified_health_data.condition.replace_date_with_onset') if raw_date.present?
        end
        return [raw_date, nil] if raw_date.blank?

        # Skip conversion for year-only (YYYY), year-month (YYYY-MM), or date-only (YYYY-MM-DD)
        return [raw_date, nil] if raw_date.match?(/\A\d{4}(-\d{2}(-\d{2})?)?\z/)

        contained = resource['contained']
        station_number = extract_station_number(contained)
        facility_timezone = facility_service.get_facility_timezone(station_number)
        converted_date = convert_to_facility_time(raw_date, facility_timezone)
        [converted_date, facility_timezone]
      end

      # Determines if a condition should be included based on its clinical status
      # Only includes conditions with clinicalStatus of 'active'
      # Conditions with no clinicalStatus or non-active status (e.g., resolved) are excluded
      #
      # @param resource [Hash] FHIR Condition resource
      # @return [Boolean] true if the condition should be included (has active clinicalStatus)
      def should_include_condition?(resource)
        clinical_status = resource.dig('clinicalStatus', 'coding', 0, 'code')

        # Only include conditions with 'active' clinical status
        # This excludes conditions with nil/missing clinicalStatus or non-active statuses like 'resolved'
        clinical_status == 'active'
      end

      def log_filtered_condition(resource)
        clinical_status = resource.dig('clinicalStatus', 'coding', 0, 'code')
        reason = clinical_status.blank? ? 'missing_clinical_status' : 'inactive_clinical_status'

        @mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CONDITIONS,
          action: 'filter',
          record_id: resource['id'],
          clinical_status:,
          reason:
        )

        StatsD.increment('unified_health_data.condition.filtered_record',
                         tags: ["reason:#{reason}"])
      end

      def extract_condition_comments(resource)
        return [] unless resource['note']

        if resource['note'].is_a?(Array)
          resource['note'].map { |note| note['text'] }.compact
        else
          [resource['note']['text']].compact
        end
      end

      def extract_condition_provider(resource)
        reference = resource.dig('recorder', 'reference')
        return '' unless reference && resource['contained']

        practitioner = find_contained_practitioner(resource, reference)
        return '' unless practitioner

        if practitioner['name'].is_a?(Array)
          name_obj = practitioner['name'].find { |n| n['text'] } || practitioner['name'].first
          name_obj['text'] || format_practitioner_name(name_obj) || ''
        else
          practitioner.dig('name', 'text') || format_practitioner_name(practitioner['name']) || ''
        end
      end

      def extract_condition_facility(resource)
        return '' unless resource['contained']

        location = resource['contained'].find { |item| item['resourceType'] == 'Location' }
        return '' unless location

        location.dig('managingOrganization', 'display') || location['name'] || ''
      end

      def find_contained_practitioner(resource, reference)
        return nil unless reference && resource['contained']

        target_id = if reference.start_with?('#')
                      reference.delete_prefix('#')
                    else
                      reference.split('/').last
                    end

        resource['contained'].find { |res| res['id'] == target_id && res['resourceType'] == 'Practitioner' }
      end

      def format_practitioner_name(name_obj)
        return nil unless name_obj.is_a?(Hash)

        if name_obj.key?('family') && name_obj.key?('given')
          firstname = name_obj['given']&.join(' ')
          lastname = name_obj['family']
          "#{firstname} #{lastname}"
        elsif name_obj['text']
          parts = name_obj['text'].split(',')
          return name_obj['text'] if parts.length != 2

          lastname, firstname = parts.map(&:strip)
          "#{firstname} #{lastname}"
        end
      end
    end
  end
end
