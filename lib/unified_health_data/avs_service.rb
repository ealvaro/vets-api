# frozen_string_literal: true

require_relative 'base_service'
require_relative 'adapters/clinical_notes_adapter'

module UnifiedHealthData
  class AvsService < UnifiedHealthData::BaseService
    # Use of this is behind va_online_scheduling_uhd_avs_metadata flipper
    def get_all_avs_metadata(start_date:, end_date:)
      validate_icn!
      start_d = (start_date || default_start_date).to_s
      end_d = (end_date || default_end_date).to_s

      if start_d > end_d
        Rails.logger.error("UHD: start_d not before end_d | start_d: #{start_d}, end_d: #{end_d}")
        return [[], []]
      end

      with_monitoring do
        response = uhd_client.get_all_avs(patient_id: @user.icn, start_date: start_d, end_date: end_d)
        parse_avs_metadata_bundle(response.body)
      end
    end

    def get_avs_binary_data(doc_id:)
      validate_icn!
      with_monitoring do
        response = uhd_client.get_by_docref(doc_id:)
        body = response.body
        summary = body['entry']&.find do |record|
          record['resource']['resourceType'] == 'DocumentReference' && record['resource']['id'] == doc_id
        end
        return nil if summary.nil?

        clinical_notes_adapter.parse_avs_binary(summary, body['entry'])
      end
    end

    private

    def parse_avs_metadata_bundle(body)
      return [[], []] if body.nil? || !body.is_a?(Hash)

      # SCDF returns a bundle: DocumentReference, Encounter, and other types.
      grouped = extract_all_entries(body).group_by { |entry| entry['resourceType'] }
      doc_ref_entries = grouped['DocumentReference'] || []
      encounter_entries = grouped['Encounter'] || []
      if doc_ref_entries.empty? || encounter_entries.empty?
        to_log = "DocumentReference entries: #{doc_ref_entries.size}, Encounter entries: #{encounter_entries.size}"
        Rails.logger.debug do
          "UHD: Missing data in AVS metadata response for user #{@user.user_account_uuid}. #{to_log}"
        end
        return [[], []]
      end
      [doc_ref_entries, encounter_entries]
    end

    def clinical_notes_adapter
      @clinical_notes_adapter ||= UnifiedHealthData::Adapters::ClinicalNotesAdapter.new(user: @user)
    end
  end
end
