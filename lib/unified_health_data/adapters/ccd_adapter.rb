# frozen_string_literal: true

require_relative '../models/ccd'
require_relative '../constants'

module UnifiedHealthData
  module Adapters
    class CcdAdapter
      PRESIGNED_URL_EXTENSION = 'http://va.gov/mhv/fhir/StructureDefinition/presigned-url'
      TASK_REFERENCE_EXTENSION = 'http://va.gov/mhv/fhir/StructureDefinition/ccd-task-reference'
      FORMAT_STATUS_EXTENSION = 'http://va.gov/mhv/fhir/StructureDefinition/ccd-format-status'

      CONTENT_TYPE_TO_FORMAT = {
        'application/xml' => :xml,
        'text/html' => :html,
        'application/pdf' => :pdf
      }.freeze

      # Parses a CCD response into a Ccd model.
      #
      # Two response shapes are possible:
      # 1. Flat JSON (from generate/status polling while not ready):
      #    { "status": "NOT_READY", "jobId": "...", ... }
      #    → Extracts job metadata; URLs will be nil.
      #
      # 2. FHIR Bundle (from status polling once ready):
      #    Contains DocumentReference + Binary resources with presigned S3 URLs.
      #    → Extracts presigned URLs and authored_on; job metadata will be nil.
      #
      # @param body [Hash] The raw API response body
      # @return [UnifiedHealthData::Ccd] Parsed CCD object
      def parse(body)
        if fhir_bundle?(body)
          parse_bundle(body)
        else
          parse_flat(body)
        end
      end

      # Parses a jobs list Bundle response into an array of Ccd models.
      # The Bundle contains Task resources with artifact metadata and OperationOutcome warnings.
      #
      # @param body [Hash] The raw FHIR Bundle response body (type: "searchset")
      # @return [Array<UnifiedHealthData::Ccd>] Array of parsed CCD job objects
      def parse_tasks(body)
        entries = body&.dig('entry') || []

        task_entries = entries.select { |e| e.dig('resource', 'resourceType') == 'Task' }

        task_entries.map { |entry| parse_task(entry['resource']) }
      end

      # Extracts the presigned S3 URL for a single requested format from a FHIR Bundle.
      #
      # @param body [Hash] The raw FHIR Bundle response body
      # @param format [String] The desired format: 'xml', 'html', or 'pdf'
      # @return [String, nil] The presigned URL for the requested format, or nil if not found
      def parse_url(body, format:)
        urls = extract_presigned_urls(body)
        urls[format.to_sym]
      end

      private

      def fhir_bundle?(body)
        body&.dig('resourceType') == 'Bundle'
      end

      # Parses a flat status/generate response into a Ccd model.
      # URLs are not available in this response shape.
      def parse_flat(body)
        body ||= {}

        UnifiedHealthData::Ccd.new(
          status: body['status'],
          job_id: body['jobId'],
          task_id: body['taskId'],
          source: body['source'],
          message: body['message'],
          retry_after_seconds: body['retryAfterSeconds'].to_i
        )
      end

      # Parses a FHIR Bundle response into a Ccd model.
      # The :xml, :html, :pdf attributes hold per-format status values (e.g. "READY")
      # extracted from each Binary resource's ccd-format-status extension.
      # Also extracts job_id (same as task_id), and
      # message from the OperationOutcome diagnostics.
      def parse_bundle(body)
        format_statuses = extract_format_statuses(body)
        task_id = extract_task_id(body)

        UnifiedHealthData::Ccd.new(
          job_id: task_id,
          task_id:,
          source: SourceConstants::ORACLE_HEALTH, # for now only applicable to OH
          message: extract_message(body),
          authored_on: extract_authored_on(body),
          **format_statuses
        )
      end

      # Extracts presigned S3 URLs from all Binary entries in a single pass.
      # Maps each Binary's contentType to the corresponding format key.
      #
      # @param body [Hash] The raw FHIR Bundle response body
      # @return [Hash] e.g. { xml: "https://...", html: "https://...", pdf: "https://..." }
      def extract_presigned_urls(body)
        entries = body&.dig('entry') || []

        binary_entries = entries.select { |e| e.dig('resource', 'resourceType') == 'Binary' }

        binary_entries.each_with_object({ xml: nil, html: nil, pdf: nil }) do |entry, urls|
          resource = entry['resource']
          content_type = resource['contentType']
          format_key = CONTENT_TYPE_TO_FORMAT[content_type]
          next unless format_key

          presigned_url = resource.dig('meta', 'extension')&.find do |ext|
            ext['url'] == PRESIGNED_URL_EXTENSION
          end&.dig('valueUrl')

          urls[format_key] = presigned_url
        end
      end

      # Extracts the per-format status from all Binary entries in a single pass.
      # Maps each Binary's contentType to the corresponding format key and reads
      # the ccd-format-status extension value (e.g. "READY").
      #
      # @param body [Hash] The raw FHIR Bundle response body
      # @return [Hash] e.g. { xml: "READY", html: "READY", pdf: "READY" }
      def extract_format_statuses(body)
        entries = body&.dig('entry') || []

        binary_entries = entries.select { |e| e.dig('resource', 'resourceType') == 'Binary' }

        binary_entries.each_with_object({ xml: nil, html: nil, pdf: nil }) do |entry, statuses|
          resource = entry['resource']
          content_type = resource['contentType']
          format_key = CONTENT_TYPE_TO_FORMAT[content_type]
          next unless format_key

          format_status = resource.dig('meta', 'extension')&.find do |ext|
            ext['url'] == FORMAT_STATUS_EXTENSION
          end&.dig('valueString')

          statuses[format_key] = format_status
        end
      end

      # Extracts the task ID from the first Binary resource's ccd-task-reference extension.
      # The extension contains a valueReference like "Task/12043"; we extract "12043".
      #
      # @param body [Hash] The raw FHIR Bundle response body
      # @return [String, nil] The task ID, or nil if not found
      def extract_task_id(body)
        entries = body&.dig('entry') || []

        binary_entry = entries.find { |e| e.dig('resource', 'resourceType') == 'Binary' }
        return nil unless binary_entry

        task_ref_ext = binary_entry.dig('resource', 'meta', 'extension')&.find do |ext|
          ext['url'] == TASK_REFERENCE_EXTENSION
        end

        reference = task_ref_ext&.dig('valueReference', 'reference')
        return nil unless reference

        # Extract the ID from "Task/12043" format
        reference.split('/').last
      end

      def extract_authored_on(body)
        entries = body&.dig('entry') || []

        doc_ref = entries.find { |e| e.dig('resource', 'resourceType') == 'DocumentReference' }
        doc_ref&.dig('resource', 'meta', 'lastUpdated')
      end

      # Extracts a message from the OperationOutcome resource's first diagnostic.
      #
      # @param body [Hash] The raw FHIR Bundle response body
      # @return [String, nil] e.g. "Success"
      def extract_message(body)
        entries = body&.dig('entry') || []

        outcome = entries.find { |e| e.dig('resource', 'resourceType') == 'OperationOutcome' }
        outcome&.dig('resource', 'issue', 0, 'diagnostics')
      end

      # Parses a single Task resource into a Ccd model.
      # The :xml, :html, :pdf attributes hold per-format status in this response shape:
      # either the artifact's failureCode (if present) or the overall businessStatus.text.
      #
      # @param resource [Hash] A FHIR Task resource
      # @return [UnifiedHealthData::Ccd]
      def parse_task(resource)
        outputs = index_task_outputs(resource['output'])
        business_status = resource.dig('businessStatus', 'text')

        UnifiedHealthData::Ccd.new(
          job_id: resource['id'],
          task_id: resource['id'],
          status: resource['status'],
          message: business_status,
          source: extract_task_source(resource),
          authored_on: resource['authoredOn'],
          xml: outputs['artifact.xml.failureCode'] || business_status,
          html: outputs['artifact.html.failureCode'] || business_status,
          pdf: outputs['artifact.pdf.failureCode'] || business_status
        )
      end

      # Indexes the Task output array into a hash keyed by output type text for O(1) lookups.
      #
      # @param outputs [Array<Hash>, nil] The Task's output array
      # @return [Hash] e.g. { "artifact.xml.s3Exists" => "true", ... }
      def index_task_outputs(outputs)
        return {} if outputs.blank?

        outputs.each_with_object({}) do |output, hash|
          key = output.dig('type', 'text')
          hash[key] = output['valueString'] if key
        end
      end

      # Extracts the source system from the Task's meta tags.
      #
      # @param resource [Hash] A FHIR Task resource
      # @return [String, nil] e.g. "oracle-health"
      def extract_task_source(resource)
        resource.dig('meta', 'tag')&.find do |tag|
          tag['system'] == 'http://va.gov/mhv/fhir/tag/source-system'
        end&.dig('code')
      end
    end
  end
end
