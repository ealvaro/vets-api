# frozen_string_literal: true

require 'medical_records/medical_records_log'
require_relative '../models/clinical_notes'
require_relative '../models/avs'
require_relative '../models/binary_data'
require_relative '../constants'
require_relative 'date_time_helpers'

module UnifiedHealthData
  module Adapters
    class ClinicalNotesAdapter
      include DateTimeHelpers
      include UnifiedHealthData::Constants

      AVS_CONTENT_TYPES = ['application/pdf', 'text/plain'].freeze

      ALLOWED_DOC_STATUSES = %w[final amended].freeze

      def initialize(user: nil)
        @mr_log = MedicalRecords::MedicalRecordsLog.new(user:)
      end

      def parse(records)
        return [] if records.blank?

        parsed = records.map { |record| parse_single_note(record) }
        parsed.compact
      end

      def parse_single_note(note)
        return nil unless note && note['resource']

        record = note['resource']

        unless allowed_doc_status?(record['docStatus'])
          reason = record['docStatus'].blank? ? 'missing_doc_status' : 'disallowed_doc_status'
          log_filtered_clinical_note(record, reason)
          return nil
        end

        note_content = get_note(record)

        # Proactive: warn when a note passes docStatus filtering but has no content.
        # Veterans see a title but click into an empty page.
        if note_content.blank?
          @mr_log.warn(
            resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
            action: 'parse',
            anomaly: 'empty_note_content',
            record_id: record['id'],
            note_type: get_record_type(record)
          )
          StatsD.increment('unified_health_data.clinical_note.empty_content')
        end

        UnifiedHealthData::ClinicalNotes.new(build_clinical_note_attributes(record, note_content,
                                                                            source: note['source']))
      end

      # The AVS is a DocumentReference FHIR type and specific type of note
      # Using a modified version of parse to add the appt_id and optionally include the binary data
      # While skipping fields that are not necessary for the AVS response
      def parse_avs_with_metadata(avs, appt_id, include_binary)
        record = avs['resource']
        avs_binary_data = extract_avs_binary(record)

        # @returns nil if pdf or plain text binary string is not available
        return nil unless record && avs_binary_data

        UnifiedHealthData::AfterVisitSummary.new({
                                                   appt_id:,
                                                   id: record['id'],
                                                   name: get_title(record),
                                                   # map to only the AVS codes
                                                   note_type: get_avs_record_type(record),
                                                   loinc_codes: get_loinc_codes(record),
                                                   content_type: avs_binary_data[:content_type],
                                                   binary: include_binary ? avs_binary_data[:binary] : nil
                                                 })
      end

      def parse_avs_binary(avs)
        record = avs['resource']
        avs_binary_data = extract_avs_binary(record)
        return nil unless record && avs_binary_data

        UnifiedHealthData::BinaryData.new(avs_binary_data)
      end

      # Builds a hash indexed by appointment ID, where each value is an array of
      # UnifiedHealthData::AfterVisitSummary objects derived from encounters and document references.
      #
      # @param encounters [Array<Hash>] FHIR Encounter resources
      # @param doc_refs [Array<Hash>] FHIR DocumentReference resources
      # @return [Hash{String => Array<UnifiedHealthData::AfterVisitSummary>}]
      def build_avs_metadata_by_appointment(encounters, doc_refs)
        doc_ref_info_by_encounter_id = build_encounter_keyed_hash_from_doc_refs(doc_refs)

        encounters.each_with_object(Hash.new { |h, k| h[k] = [] }) do |encounter, memo|
          next unless encounter.is_a?(Hash) && encounter['id'].present?

          enc_id = encounter['id']
          meta = doc_ref_info_by_encounter_id[enc_id] || {}

          Array(encounter['appointment']).each do |appt_ref|
            appt_id = extract_reference_id(appt_ref['reference'], 'Appointment')
            next if appt_id.blank?

            memo[appt_id] << UnifiedHealthData::AfterVisitSummary.new(
              id: meta[:doc_ref_id],
              appt_id:,
              name: meta[:title] || 'other',
              note_type: meta[:note_type],
              loinc_codes: meta[:loinc],
              content_type: meta[:content_types]&.first,
              binary: nil
            )
          end
        end
      end

      private

      def build_clinical_note_attributes(record, note_content, source: nil)
        if addendum_note?(record)
          build_addendum_attributes(record, note_content, source:)
        else
          build_standard_attributes(record, note_content, source:)
        end
      end

      # Builds attributes for a standard (non-addendum) note.
      def build_standard_attributes(record, note_content, source: nil)
        date_value = source == SourceConstants::ORACLE_HEALTH ? derive_oh_date(record) : record['date']

        {
          id: record['id'],
          name: get_title(record),
          note_type: get_record_type(record),
          loinc_codes: get_loinc_codes(record),
          date: date_value,
          sort_date: normalize_date_for_sorting(date_value),
          date_signed: get_date_signed(record),
          written_by: extract_author(record),
          signed_by: extract_authenticator(record),
          location: extract_location(record),
          admission_date: record['context']&.dig('period', 'start') || nil,
          discharge_date: record['context']&.dig('period', 'end') || nil,
          note: note_content,
          addenda: nil,
          source:
        }
      end

      # Builds attributes for an addendum note. The outer record is the newest addendum;
      # the contained DocumentReferences referenced by relatesTo are the original note
      # plus any intermediate addenda.
      #
      # Strategy:
      #   1. Resolve every relatesTo[code=appends] reference to a contained DocumentReference.
      #   2. Sort them by date ascending — the oldest is the original note.
      #   3. Everything else (intermediate contained docs + the outer record) becomes an
      #      addendum entry, sorted oldest-to-newest.
      def build_addendum_attributes(record, addendum_content, source: nil) # rubocop:disable Metrics/MethodLength
        appended_docs = get_all_appended_documents(record)

        # If no contained docs could be resolved, fall back to standard behavior.
        return build_standard_attributes(record, addendum_content, source:) if appended_docs.empty?

        # Contained DocumentReferences don't carry their own nested `contained` array,
        # but they reference Practitioners that live in the outer record's `contained`.
        # Pass the outer record's `contained` so those references can be resolved.
        parent_contained = record['contained'] || []

        # Sort by date ascending; the oldest document is the original note.
        sorted_docs = appended_docs.sort_by do |doc|
          normalize_date_for_sorting(doc['date'] || record['date'] || '')
        end
        original_doc = sorted_docs.first
        intermediate_docs = sorted_docs.drop(1)

        original_content = get_note(original_doc)
        date_value = if source == SourceConstants::ORACLE_HEALTH
                       derive_oh_date(original_doc, fallback_record: record)
                     else
                       original_doc['date'] || record['date']
                     end

        # Build addenda: intermediate contained docs (oldest first), then the outer record (newest).
        addenda = intermediate_docs.filter_map { |doc| build_addendum_entry(doc, parent_contained:) }
        addenda << build_addendum_entry(record, content: addendum_content) if addendum_content.present?

        {
          id: record['id'],
          name: get_title(original_doc) || get_title(record),
          note_type: get_record_type(original_doc),
          loinc_codes: get_loinc_codes(original_doc),
          date: date_value,
          sort_date: normalize_date_for_sorting(date_value),
          date_signed: get_date_signed(original_doc) || get_date_signed(record),
          written_by: extract_author(original_doc, contained: parent_contained) || extract_author(record),
          signed_by: extract_authenticator(original_doc, contained: parent_contained) || extract_authenticator(record),
          location: extract_location(original_doc, contained: parent_contained) || extract_location(record),
          admission_date: original_doc['context']&.dig('period', 'start') || nil,
          discharge_date: original_doc['context']&.dig('period', 'end') || nil,
          note: original_content || addendum_content,
          addenda: addenda.compact,
          source:
        }
      end # rubocop:enable Metrics/MethodLength

      def allowed_doc_status?(doc_status)
        ALLOWED_DOC_STATUSES.include?(doc_status&.downcase)
      end

      # For Oracle Health notes, derive date from context.period (encounter timing) rather than
      # DocumentReference.date. Falls back to DocumentReference.date only when the author is NOT
      # the TIU system contributor (HX_VA_TIU_SYS), whose DocumentReference.date is unreliable.
      #
      # Precedence: context.period.start > context.period.end > DocumentReference.date (if non-TIU)
      #
      # @param record [Hash] FHIR DocumentReference resource
      # @param fallback_record [Hash, nil] outer record to check for context.period (for addenda)
      # @return [String, nil] the derived date, or nil if no usable date is available
      def derive_oh_date(record, fallback_record: nil)
        start_date = record.dig('context', 'period', 'start') ||
                     fallback_record&.dig('context', 'period', 'start')
        end_date = record.dig('context', 'period', 'end') ||
                   fallback_record&.dig('context', 'period', 'end')
        encounter_date = start_date || end_date
        return encounter_date if encounter_date.present?

        # No encounter date available — only fall back to DocumentReference.date
        # if the author is NOT the TIU system contributor.
        tiu_system_author?(record) ? nil : record['date']
      end

      def tiu_system_author?(record)
        Array(record['author']).any? { |a| a['display']&.include?('HX_VA_TIU_SYS') }
      end

      # Builds a slim hash for entries in the `addenda` array of an addendum record.
      # Omits fields that are redundant with the top-level record (note_type, loinc_codes,
      # id, location, source, name, admission_date, discharge_date) to avoid redundancy.
      #
      # @param doc [Hash] A FHIR DocumentReference resource (original or addendum)
      # @param content [String, nil] Pre-extracted note content
      # @param parent_contained [Array, nil] The outer record's `contained` array, used to
      #   resolve practitioner references that live outside the contained doc itself
      # @return [Hash, nil] Hash with addendum-relevant fields, or nil if content is missing
      def build_addendum_entry(doc, content: nil, parent_contained: nil)
        content ||= get_note(doc)
        return nil if content.blank?

        {
          date: doc['date'],
          date_signed: get_date_signed(doc),
          written_by: extract_author(doc, contained: parent_contained || doc['contained']),
          signed_by: extract_authenticator(doc, contained: parent_contained || doc['contained']),
          note: content
        }
      rescue NoMethodError, KeyError, TypeError => e
        @mr_log.warn(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'build_addendum_entry',
          anomaly: 'note_entry_skipped',
          record_id: doc&.dig('id'),
          error_class: e.class.name,
          error_message: e.message
        )
        StatsD.increment('unified_health_data.clinical_note.note_entry_skipped')
        nil
      end

      # Returns true if the record has a relatesTo entry with code "appends",
      # indicating it is an addendum to another note.
      def addendum_note?(record)
        return false unless array_and_has_items(record['relatesTo'])

        record['relatesTo'].any? { |r| r['code'] == 'appends' }
      end

      # Resolves all relatesTo[code=appends] references to contained DocumentReference
      # resources. Returns an array of document hashes (may be empty).
      #
      # @param record [Hash] The outer FHIR DocumentReference resource
      # @return [Array<Hash>] Contained DocumentReference resources referenced by relatesTo
      def get_all_appended_documents(record)
        return [] unless array_and_has_items(record['relatesTo'])

        record['relatesTo']
          .select { |r| r['code'] == 'appends' }
          .filter_map do |relates_to_entry|
            reference = relates_to_entry.dig('target', 'reference')
            next unless reference

            find_contained(record['contained'], reference, FHIR_RESOURCE_TYPES[:DOCUMENT_REFERENCE])
          end
      rescue NoMethodError, KeyError, TypeError => e
        @mr_log.warn(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'get_all_appended_documents',
          anomaly: 'appended_documents_extraction_failed',
          record_id: record&.dig('id'),
          error_class: e.class.name,
          error_message: e.message
        )
        []
      end

      def log_filtered_clinical_note(record, reason)
        @mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'filter',
          record_id: record['id'],
          doc_status: record['docStatus'],
          reason:
        )

        StatsD.increment('unified_health_data.clinical_note.filtered_document_reference',
                         tags: ["reason:#{reason}"])
      end

      def get_record_type(record)
        coding = record.dig('type', 'coding')
        LOINC_CODES.each do |key, value|
          return value if coding&.any? { |c| c['code'] == key }
        end

        # Diagnostic: log when a LOINC code is not in our known mapping.
        # Toggle-gated because LOINC_CODES only has 3 entries, so many legitimate
        # codes (e.g. AVS codes) will hit this path in normal operation.
        # StatsD counter still fires always-on for DataDog monitoring.
        codes = coding&.map { |c| c['code'] }&.compact
        @mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'parse',
          anomaly: 'unknown_loinc_code',
          record_id: record['id'],
          loinc_codes: codes&.join(',')
        )
        StatsD.increment('unified_health_data.clinical_note.unknown_loinc_code')

        'other'
      end

      def get_avs_record_type(record)
        coding = record.dig('type', 'coding')
        AVS_LOINC_CODE_MAPPING.each do |key, value|
          return value if coding&.any? { |c| c['code'] == key }
        end
        'other'
      end

      def get_loinc_codes(record)
        record.dig('type', 'coding')&.map { |coding| coding['code'] if coding['code'] }
      end

      def build_encounter_keyed_hash_from_doc_refs(document_references)
        document_references.each_with_object({}) do |doc_ref, memo|
          codes = get_loinc_codes(doc_ref)
          content_types = Array(doc_ref['content'])
                          .filter_map { |c| c.dig('attachment', 'contentType') if c.is_a?(Hash) }
                          .select { |ct| AVS_CONTENT_TYPES.include?(ct) }
          record_type = get_avs_record_type(doc_ref)
          title = get_title(doc_ref)
          next if codes.blank? && content_types.blank?

          Array(doc_ref.dig('context', 'encounter')).each do |enc_ref|
            enc_id = extract_reference_id(enc_ref['reference'], 'Encounter')
            next if enc_id.blank?

            memo[enc_id] ||= { loinc: [], content_types: [], note_type: nil, title: nil, doc_ref_id: nil }
            memo[enc_id][:loinc] |= codes.compact if codes.present?
            memo[enc_id][:content_types] |= Array(content_types) if content_types.present?
            memo[enc_id][:note_type] ||= record_type if record_type.present?
            memo[enc_id][:title] ||= title if title.present?
            memo[enc_id][:doc_ref_id] ||= doc_ref['id'] if doc_ref['id'].present?
          end
        end
      end

      def extract_reference_id(reference, expected_resource_type)
        return nil unless reference.is_a?(String)

        resource_prefix = "#{expected_resource_type}/"
        return nil unless reference.start_with?(resource_prefix)

        reference.delete_prefix(resource_prefix).presence
      end

      def array_and_has_items(item)
        item.is_a?(Array) && !item.empty?
      end

      def get_title(record)
        content_item = record['content']&.find { |item| item['attachment'] }
        return nil unless content_item
        return content_item['attachment']['title'] if content_item.dig('attachment', 'title')

        record.dig('type', 'text')
      rescue
        nil
      end

      def extract_authenticator(record, contained: nil)
        contained ||= record['contained']
        # Should work for both VistA and OH formats.
        authenticator = find_contained(
          contained,
          record['authenticator']['reference'],
          FHIR_RESOURCE_TYPES[:PRACTITIONER]
        )
        name = authenticator['name']&.find { |n| n['text'] }
        format_name_first_to_last(name) if name
      rescue
        nil
      end

      def extract_author(record, contained: nil)
        contained ||= record['contained']
        # Should work for both VistA and OH formats.
        if array_and_has_items(record['author'])
          author_ref = record['author'].find { |a| a['reference'] }
          author = find_contained(contained, author_ref['reference'], FHIR_RESOURCE_TYPES[:PRACTITIONER])
          name = author['name']&.find { |n| n['text'] }
          format_name_first_to_last(name) if name
        end
      rescue
        nil
      end

      def format_name_first_to_last(name)
        if name.is_a?(Hash)
          if name.key?('family') && name.key?('given')
            firstname = name['given']&.join(' ')
            lastname = name['family']
            return "#{firstname} #{lastname}"
          end

          parts = name['text']&.split(',')
          return name['text'] if parts&.length != 2

          lastname, firstname = parts
          return "#{firstname} #{lastname}"
        end

        parts = name.split(',')
        return name if parts.length != 2

        lastname, firstname = parts
        "#{firstname} #{lastname}"
      rescue
        nil
      end

      def extract_location(record, contained: nil)
        contained ||= record['contained']
        # VistA - location is in the context.related array
        if array_and_has_items(record['context']['related'])
          reference = record['context']['related'].find { |r| r['reference'] }['reference']
          if reference
            resource = find_contained(contained, reference)
            resource.dig('managingOrganization', 'display') || resource['name']
          end
        # OH - location is in the custodian field
        elsif record['custodian']['reference']
          resource = find_contained(contained, record['custodian']['reference'], FHIR_RESOURCE_TYPES[:LOCATION])
          resource.dig('managingOrganization', 'display') || resource['name']
        end
      rescue
        nil
      end

      def extract_avs_binary(record)
        # First check contained to see if we get an item with content type either pdf or plain text
        # in the contained array with a data string
        if array_and_has_items(record['contained'])
          resource = record['contained'].find do |res|
            res['resourceType'] == FHIR_RESOURCE_TYPES[:BINARY]
          end
          if resource && resource['data'] && AVS_CONTENT_TYPES.include?(resource['contentType'])
            return { content_type: resource['contentType'], binary: resource['data'] }
          end
        end

        # Fallback check for pdf or plain text with data string in the content array
        if array_and_has_items(record['content'])
          content_item = record['content'].find do |item|
            item.dig('attachment', 'data') && AVS_CONTENT_TYPES.include?(item.dig('attachment', 'contentType'))
          end

          if content_item
            return { content_type: content_item['attachment']['contentType'],
                     binary: content_item['attachment']['data'] }
          end
        end
        nil
      end

      def get_note(record)
        if array_and_has_items(record['content'])
          content_item = record['content'].find { |item| item.dig('attachment', 'contentType') == 'text/plain' }
          return nil unless content_item

          content_item.dig('attachment', 'data')
        end
      rescue
        nil
      end

      # Signing date does not seem to exist in OH data
      def get_date_signed(record)
        if array_and_has_items(record['authenticator']['extension'])
          record['authenticator']['extension'].find { |e| e['valueDateTime'] }['valueDateTime']
        end
      rescue
        nil
      end

      def find_contained(contained, reference, type = nil)
        return nil unless reference && contained

        if reference.start_with?('#')
          # Reference is in the format #mhv-resourceType-id
          target_id = reference.delete_prefix('#')
          resource = contained.detect { |res| res['id'] == target_id }
          return nil unless resource && (type.nil? || resource['resourceType'] == type)
        else
          # Reference is in the format ResourceType/id
          type_id = reference.split('/')
          resource = contained.detect { |res| res['id'] == type_id.last }
          return nil unless resource && (resource['resourceType'] == type_id.first || resource['resourceType'] == type)
        end
        resource
      end
    end
  end
end
