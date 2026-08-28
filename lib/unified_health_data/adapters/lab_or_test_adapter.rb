# frozen_string_literal: true

require_relative '../models/lab_or_test'
require_relative '../reference_range_formatter'
require_relative '../facility_service'
require_relative '../constants'
require_relative '../concerns/labs_and_tests_logging'
require_relative 'date_time_helpers'
require_relative 'fhir_helpers'
require_relative 'station_helpers'
require 'medical_records/medical_records_log'

module UnifiedHealthData
  module Adapters
    class LabOrTestAdapter
      include Concerns::LabsAndTestsLogging
      include UnifiedHealthData::Constants
      include DateTimeHelpers
      include FhirHelpers
      include StationHelpers

      ALLOWED_STATUSES = %w[final amended corrected appended].freeze
      VISTA_HOSTNAME_PATTERN = /\.MED\.VA\.GOV$/i

      # @param mr_log [MedicalRecords::MedicalRecordsLog, nil] Structured logger (nil = Rails.logger fallback)
      def initialize(mr_log: nil)
        @mr_log = mr_log
      end

      def parse_labs(records)
        return [] if records.blank?

        filtered = records.select do |record|
          record['resource'] && record['resource']['resourceType'] == 'DiagnosticReport'
        end
        filtered.filter_map do |record|
          parse_single_record(record)
        rescue Common::Exceptions::BaseError
          raise
        rescue => e
          log_record_parse_failure(record, e)
          nil
        end
      end

      private

      def parse_single_record(record)
        return nil if record.nil? || record['resource'].nil?

        # Filter out DiagnosticReports with disallowed status
        unless allowed_status?(record['resource']['status'])
          log_filtered_diagnostic_report(record, 'disallowed_status')
          return nil
        end

        contained = record['resource']['contained']
        code = get_code(record)
        encoded_data = get_encoded_data(record['resource'])
        observations = get_observations(record)

        # Log warnings before filtering out records
        log_warnings(record, encoded_data, observations)

        # Return nil if there's no code, and if there's no encoded data AND no valid observations
        unless code && (encoded_data.present? || observations.any?)
          log_filtered_diagnostic_report(record, 'no_valid_data')
          return nil
        end

        build_lab_or_test(record, code, encoded_data, observations, contained)
      end

      def allowed_status?(status)
        ALLOWED_STATUSES.include?(status)
      end

      def build_lab_or_test(record, code, encoded_data, observations, contained) # rubocop:disable Metrics/MethodLength
        resource = record['resource']
        date_completed_value, facility_timezone = resolve_date_and_timezone(resource, contained)

        UnifiedHealthData::LabOrTest.new(
          id: resource['id'],
          type: resource['resourceType'],
          display: format_display(resource, record['source']),
          test_code: code,
          test_code_display: get_test_code_display(record, code),
          date_completed: date_completed_value,
          sort_date: normalize_date_for_sorting(date_completed_value),
          sample_tested: get_sample_tested(resource, contained),
          encoded_data:,
          location: get_location(record),
          ordered_by: get_ordered_by(record),
          comments: extract_comments(record),
          observations:,
          body_site: get_body_site(resource, contained),
          status: resource['status'],
          source: record['source'],
          facility_timezone:,
          vista_id: extract_vista_id(resource)
        )
      end # rubocop:enable Metrics/MethodLength

      # TODO: See if we can tap into the memoized version in Rx expiration helper
      # (see facility_timezone_for method in oracle_health_expiration_helper)
      #
      # Resolves date_completed and facility_timezone by extracting station number
      # and converting UTC to facility local time when possible
      def resolve_date_and_timezone(resource, contained)
        raw_date = get_date_completed(resource)
        station_number = extract_station_number(contained)
        facility_timezone = facility_service.get_facility_timezone(station_number)
        date_completed = convert_to_facility_time(raw_date, facility_timezone)
        [date_completed, facility_timezone]
      end

      def get_location(record)
        contained = record.dig('resource', 'contained')
        return nil if contained.nil?

        performers = record.dig('resource', 'performer') || []
        performer_ref_ids = performers.map { |p| get_reference_id(p['reference']) }.compact

        match = contained.find do |r|
          %w[Organization Location].include?(r['resourceType']) &&
            performer_ref_ids.include?(r['id'])
        end

        name = location_display_name(match)

        if name.present? && match['resourceType'] == 'Organization' && name.match?(VISTA_HOSTNAME_PATTERN)
          return resolve_hostname_location(match)
        end

        return name if name.present?

        # Fallback: first Organization or Location in contained order.
        # VistA records typically use Organization; OH records use Location.
        fallback = contained.find { |r| %w[Organization Location].include?(r['resourceType']) }
        location_display_name(fallback)
      end

      # Prefer managingOrganization.display for Location resources (stable facility name),
      # fall back to resource name. Organization resources always use name directly.
      def location_display_name(resource)
        return nil if resource.nil?

        if resource['resourceType'] == 'Location'
          resource.dig('managingOrganization', 'display') || resource['name']
        else
          resource['name']
        end
      end

      # Falls back to resource.code.coding when the only category is LAB
      def get_code(record)
        category_code(record) || report_code(record['resource'])
      end

      def category_code(record)
        return nil if record['resource']['category'].blank?

        coding = record['resource']['category'].find do |category|
          category['coding'].present? && category['coding'][0]['code'] != 'LAB'
        end
        coding ? coding['coding'][0]['code'] : nil
      end

      def report_code(resource)
        codings = resource.dig('code', 'coding')
        return nil if codings.blank?

        loinc = codings.find { |c| c['system'] == 'http://loinc.org' && c['code'].present? }
        (loinc || codings.find { |c| c['code'].present? })&.dig('code')
      end

      # Normalize code for display mapping only (preserves raw code in test_code field)
      # Extracts 2-letter code from VistA URN format: "urn:va:lab-category:MI" -> "MI"
      def normalize_code_for_display(code)
        return code if code.nil?

        code.match(/urn:va:lab-category:(\w+)/)&.captures&.first || code
      end

      # Get the display name for a test code with fallback chain:
      # 1. Check TEST_CODE_DISPLAY_MAP (using normalized code)
      # 2. Fall back to category.coding.display from the FHIR data
      # 3. Fall back to category.text from the FHIR data
      # 4. Final fallback: the normalized code itself
      def get_test_code_display(record, code)
        normalized_code = normalize_code_for_display(code)

        # First, check our explicit mapping
        return TEST_CODE_DISPLAY_MAP[normalized_code] if TEST_CODE_DISPLAY_MAP.key?(normalized_code)

        # Fall back to display/text from the category coding in FHIR data
        category_display = get_category_display(record)
        return category_display if category_display.present?

        # Fall back to display/text from resource.code (for LOINC-fallback records)
        report_display = extract_codeable_concept_display(record['resource']['code'], prefer: :coding)
        return report_display if report_display.present?

        # Final fallback: use the normalized code
        normalized_code
      end

      # Extract display or text from the category that has the test code
      def get_category_display(record)
        return nil if record['resource']['category'].blank?

        category = record['resource']['category'].find do |cat|
          cat['coding'].present? && cat['coding'][0]['code'] != 'LAB'
        end
        return nil unless category

        # Try coding.display first, then category.text
        extract_codeable_concept_display(category, prefer: :coding)
      end

      def extract_comments(record)
        resource = record['resource']
        comments = []

        # Extract comments from DiagnosticReport extensions (VistA labComment extensions)
        if resource['extension'].present?
          extension_comments = resource['extension'].filter_map { |ext| ext['valueString'] }
          comments.concat(extension_comments)
        end

        # Extract comments from ServiceRequest.note[].text in contained resources (Oracle Health)
        if resource['basedOn'].present? && resource['contained'].present?
          resource['basedOn'].each do |based_on|
            service_request = resource['contained'].find do |r|
              r['resourceType'] == 'ServiceRequest' && r['id'] == get_reference_id(based_on['reference'])
            end

            next unless service_request&.dig('note').is_a?(Array)

            note_comments = service_request['note'].filter_map { |note| note['text'] }
            comments.concat(note_comments)
          end
        end

        comments.presence
      end

      def get_body_site(resource, contained)
        return '' unless resource['basedOn']
        return '' if contained.nil?

        body_sites = []

        resource['basedOn'].each do |based_on|
          service_request = contained.find do |r|
            r['resourceType'] == 'ServiceRequest' && r['id'] == get_reference_id(based_on['reference'])
          end

          next unless service_request&.dig('bodySite')

          service_request['bodySite'].each do |body_site|
            # Prefer coding display (VistA uses this), fall back to CodeableConcept text (OH uses this)
            display = extract_codeable_concept_display(body_site, prefer: :coding)
            body_sites << display if display.present?
          end
        end

        body_sites.join(', ').strip
      end

      def get_sample_tested(record, contained)
        return '' unless record['specimen']
        return '' if contained.nil?

        specimen_references = if record['specimen'].is_a?(Hash)
                                [get_reference_id(record['specimen']['reference'])]
                              elsif record['specimen'].is_a?(Array)
                                record['specimen'].map { |specimen| get_reference_id(specimen['reference']) }
                              end

        specimens =
          specimen_references.map do |reference|
            specimen_object = contained.find do |resource|
              resource['resourceType'] == 'Specimen' && resource['id'] == reference
            end
            specimen_object&.dig('type', 'text')
          end

        specimens.compact.join(', ').strip
      end

      def get_observations(record)
        return [] if record['resource']['contained'].nil?

        all_observations = record['resource']['contained'].select do |resource|
          resource['resourceType'] == 'Observation'
        end

        valid_observations, filtered_count = parse_valid_observations(all_observations, record)

        # Log and track filtered observations
        log_filtered_observations(record, filtered_count, all_observations.size) if filtered_count.positive?

        valid_observations
      end

      def parse_valid_observations(all_observations, record)
        filtered_count = 0

        valid = all_observations.filter_map do |obs|
          unless allowed_status?(obs['status'])
            filtered_count += 1
            next
          end

          begin
            build_observation(obs, record['resource']['contained'])
          rescue Common::Exceptions::BaseError
            raise
          rescue => e
            log_observation_parse_failure(record, obs, e)
            nil
          end
        end

        [valid, filtered_count]
      end

      def build_observation(obs, contained)
        sample_tested = get_sample_tested(obs, contained)
        body_site = get_body_site(obs, contained)
        UnifiedHealthData::Observation.new(
          test_code: obs['code']['text'],
          value: format_observation_value(obs),
          reference_range: UnifiedHealthData::ReferenceRangeFormatter.format(obs),
          status: obs['status'],
          interpretation: extract_interpretation(obs),
          comments: obs['note']&.map { |note| note['text'] }&.compact || [],
          sample_tested:,
          body_site:
        )
      end

      def extract_interpretation(obs)
        interpretations = obs['interpretation']
        return nil if interpretations.blank?

        fallback_text = nil
        fallback_code = nil

        interpretations.each do |interp|
          if interp['coding'].present?
            hl7_coding = interp['coding'].find do |coding|
              coding['system']&.include?('v3-ObservationInterpretation') && coding['code'].present?
            end
            if hl7_coding
              # Priority 1: Mapped human-friendly display from INTERPRETATION_MAP
              mapped = INTERPRETATION_MAP[hl7_coding['code']]
              return mapped if mapped.present?

              # Capture raw code as absolute last resort fallback
              fallback_code ||= hl7_coding['code']
            end
          end

          # Priority 2: text or coding.display from the CodeableConcept
          fallback_text ||= extract_codeable_concept_display(interp)
        end

        # Prefer human-readable text/display over raw code
        fallback_text || fallback_code
      end

      def format_observation_value(obs)
        type, text = if obs['valueQuantity']
                       ['quantity', format_quantity_value(obs['valueQuantity'])]
                     elsif obs['valueCodeableConcept']
                       ['codeable-concept', obs['valueCodeableConcept']['text']]
                     elsif obs['valueString']
                       ['string', obs['valueString']]
                     elsif obs['valueDateTime']
                       ['date-time', obs['valueDateTime']]
                     elsif obs['valueAttachment']
                       log_adapter(
                         :error,
                         { resource: LABS, action: 'parse', anomaly: 'unsupported_value_type',
                           observation_id: obs['id'], value_type: 'Attachment' },
                         { message: "Observation with ID #{obs['id']} has unsupported value type: Attachment" }
                       )
                       raise Common::Exceptions::NotImplemented
                     else
                       [nil, nil]
                     end
        { text:, type: }
      end

      def format_quantity_value(value_quantity)
        value = value_quantity['value']
        unit = value_quantity['unit']
        comparator = value_quantity['comparator']

        result_text = ''
        result_text += comparator.to_s if comparator.present?
        result_text += value.to_s
        result_text += " #{unit}" if unit.present?

        result_text
      end

      def get_ordered_by(record)
        contained = record.dig('resource', 'contained')
        return nil if contained.nil?

        service_request = contained.find { |r| r['resourceType'] == 'ServiceRequest' }
        requester = service_request&.dig('requester')
        return nil unless requester

        requester_id = get_reference_id(requester['reference'])
        practitioner = contained.find do |r|
          r['resourceType'] == 'Practitioner' && r['id'] == requester_id
        end

        if practitioner
          name = practitioner['name']&.first
          return requester['display'] unless name

          given = name['given']&.join(' ')
          family = name['family']
          "#{given} #{family}".strip
        else
          # OH records may include a display name on the requester when the Practitioner
          # is not embedded in the contained array
          requester['display']
        end
      end

      def get_reference_id(reference)
        return nil if reference.blank?
        # Some of the VistA data doesn't use the full reference format, and instead just has the ID,
        # so we need to handle both cases
        return reference if reference&.exclude?('/')

        reference.split('/').last
      end

      def format_display(resource, source = nil)
        # Check presentedForm title first (e.g., radiology reports) — applies to all sources
        title = resource['presentedForm']
                &.find { |form| form['contentType'] == 'text/plain' }
                &.dig('title')
        return title if title.present?

        if source == UnifiedHealthData::SourceConstants::ORACLE_HEALTH
          format_display_oracle_health(resource)
        else
          format_display_vista(resource)
        end
      end

      def format_display_oracle_health(resource)
        # 1. ServiceRequest.code.text
        service_request = resource['contained']&.find { |r| r['resourceType'] == 'ServiceRequest' }
        service_request_code_text = service_request&.dig('code', 'text')
        return service_request_code_text if service_request_code_text.present?

        # 2. First category.coding.display
        resource['category']&.each do |cat|
          coding_display = first_coding_display(cat)
          return coding_display if coding_display.present?
        end

        # 3. Fall back to code.text
        code_display = extract_codeable_concept_display(resource['code'])
        return code_display if code_display.present?

        ''
      end

      def format_display_vista(resource)
        # Top-level code.text, then first found code.coding.display
        code_display = extract_codeable_concept_display(resource['code'])
        return code_display if code_display.present?

        # Fallback to contained ServiceRequest
        service_request = resource['contained']&.find { |r| r['resourceType'] == 'ServiceRequest' }

        service_request&.dig('code', 'text').presence ||
          service_request&.dig('category', 0, 'coding', 0, 'display').presence ||
          ''
      end

      def get_encoded_data(resource)
        return '' unless resource['presentedForm']&.any?

        # Find the presentedForm item with contentType 'text/plain'
        presented_form = resource['presentedForm'].find { |form| form['contentType'] == 'text/plain' }
        return '' unless presented_form

        # Handle standard data field or extensions indicating data-absent-reason
        # Return empty string when data is absent (either with data-absent-reason extension or missing)
        presented_form['data'] || ''
      end

      def get_date_completed(resource)
        # Handle both effectiveDateTime and effectivePeriod formats
        if resource['effectiveDateTime']
          resource['effectiveDateTime']
        elsif resource['effectivePeriod']&.dig('start')
          resource['effectivePeriod']['start']
        # Fallback to report's creation date if no other dates available
        elsif resource['presentedForm']
          resource['presentedForm'].find { |form| form['contentType'] == 'text/plain' }&.dig('creation')
        end
      end

      # Extracts the VistA-native identifier (system='vista-id') from the FHIR resource.
      # Used for cross-referencing imaging studies with radiology reports.
      #
      # @param resource [Hash] FHIR DiagnosticReport resource
      # @return [String, nil] the vista-id value or nil
      def extract_vista_id(resource)
        return nil if resource['identifier'].blank?

        vista_identifier = resource['identifier'].find { |id| id['system'] == 'vista-id' }
        vista_identifier&.dig('value')
      end

      def facility_service
        @facility_service ||= UnifiedHealthData::FacilityService.new
      end
    end
  end
end
