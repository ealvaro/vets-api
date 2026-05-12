# frozen_string_literal: true

require 'common/client/base'
require 'common/exceptions/not_implemented'
require_relative 'configuration'
require_relative 'client'
require_relative 'constants'

module UnifiedHealthData
  class BaseService
    include Common::Client::Concerns::Monitoring
    include Constants

    def initialize(user)
      super()
      @user = user
    end

    # Extracts all resource hashes from a FHIR Bundle's entry array.
    def extract_all_entries(bundle)
      return [] unless bundle.is_a?(Hash)

      inner = bundle['resource'] || bundle
      entries = inner['entry']
      return [] unless entries.is_a?(Array)

      entries.filter_map { |entry| entry['resource'] }
    end

    # Extracts and removes warning metadata injected by the client's OperationOutcome detection.
    # Returns an empty array if no warnings are present.
    def extract_warnings(body)
      return [] unless body.is_a?(Hash)

      body.delete('_warnings') || []
    end

    def fetch_combined_records(body)
      return [] if body.nil?

      vista_records = (body.dig(SourceConstants::VISTA, 'entry') || []).map do |r|
        r.merge('source' => SourceConstants::VISTA)
      end
      oracle_health_records = (body.dig(SourceConstants::ORACLE_HEALTH, 'entry') || []).map do |r|
        r.merge('source' => SourceConstants::ORACLE_HEALTH)
      end
      vista_records + oracle_health_records
    end

    # SCDF always returns Bundles from Oracle Health
    def extract_bundle(body, resource_type)
      return nil unless body.is_a?(Hash)

      entries = body['entry']
      return nil unless entries.is_a?(Array)

      resource_entry = entries.find do |entry|
        entry.dig('resource', 'resourceType') == resource_type
      end
      resource_entry&.dig('resource')
    end

    def remap_vista_identifier(records)
      records[SourceConstants::VISTA]['entry']&.each do |allergy|
        vista_identifier = allergy['resource']['identifier']&.find do |id|
          id['system'].starts_with?('https://va.gov/systems/')
        end
        next unless vista_identifier && vista_identifier['value']

        allergy['resource']['id'] = vista_identifier['value']
      end
    end

    def remap_vista_uid(records)
      records[SourceConstants::VISTA]['entry']&.each do |note|
        vista_uid_identifier = note['resource']['identifier']&.find { |id| id['system'] == 'vista-uid' }
        next unless vista_uid_identifier && vista_uid_identifier['value']

        new_id_array = vista_uid_identifier['value'].split(':')
        note['resource']['id'] = new_id_array[-3..].join('-')
      end
    end

    def uhd_client
      @uhd_client ||= UnifiedHealthData::Client.new
    end

    def validate_icn!
      raise Common::Exceptions::ParameterMissing, 'ICN' if @user&.icn.blank?
    end

    def default_start_date
      '1900-01-01'
    end

    def default_end_date
      Time.zone.today.to_s
    end

    def validate_date_param(date_string, param_name)
      Date.parse(date_string)
    rescue ArgumentError, TypeError
      raise ArgumentError, "Invalid #{param_name}: '#{date_string}'. Expected format: YYYY-MM-DD"
    end

    def normalize_date_range(start_date, end_date)
      start_date = nil if start_date.blank?
      end_date = nil if end_date.blank?
      validate_date_param(start_date, 'start_date') if start_date
      validate_date_param(end_date, 'end_date') if end_date
      [start_date || default_start_date, end_date || default_end_date]
    end
  end
end
