# frozen_string_literal: true

require 'cave/field_catalog'
require 'cave/value_normalizer'

module Cave
  # Builds the "system generated" change log documenting which CAVE-extracted fields
  # a user corrected on review. The output is used two ways:
  #   1. rendered into the VA Form 21-4138 Remarks (so downstream reviewers can see the
  #      adjustments), and
  #   2. forwarded to CAVE as accuracy-metrics feedback (corrections tracking).
  #
  # For each CaveSubmission on a claim it compares the OCR-extracted values
  # (CaveSubmission#cave_response, raw SCREAMING_SNAKE strings) against the user-final
  # values the frontend submits in form_data['files'][*]['idpArtifacts'] (already
  # normalized, camelCase), emitting one Record per CHANGED field. Comparison is done on
  # canonicalized values (see Cave::ValueNormalizer) so a field that merely changed shape
  # is not reported as a user edit.
  class ChangeLog
    HEADER = 'SYSTEM GENERATED TO DOCUMENT USER CHANGES'
    NO_CHANGES_LINE = 'No user changes were made to the extracted document data.'
    EMPTY_DISPLAY = '(none)'

    Record = Struct.new(:document_name, :field, :label, :ocr_value, :user_value, keyword_init: true) do
      def to_h
        { field:, label:, ocr_value:, user_value: }
      end
    end

    # @param cave_submissions [Enumerable<CaveSubmission>] submissions linked to the claim
    # @param form_data [Hash] the parsed claim form (provides files[].idpArtifacts)
    def initialize(cave_submissions:, form_data:)
      @cave_submissions = Array(cave_submissions)
      @form_data = form_data || {}
    end

    # @return [Array<Record>] one entry per changed field across all documents
    def records
      submission_diffs.flat_map { |diff| diff[:records] }
    end

    # @return [Array<Record>] changed-field records for a single submission
    def records_for(cave_submission)
      diff = submission_diffs.find { |d| d[:submission] == cave_submission }
      diff ? diff[:records] : []
    end

    # @return [String] the formatted Remarks string (header + per-document grouping).
    #   Always non-empty so the 21-4138 PdfSchema's required(:remarks) is satisfied.
    def remarks
      lines = [HEADER]

      if records.empty?
        lines << NO_CHANGES_LINE
      else
        records.group_by(&:document_name).each do |document_name, doc_records|
          lines << document_name
          doc_records.each do |record|
            lines << "#{record.label}: OCR Extracted Value: #{record.ocr_value}; " \
                     "User Updated Value: #{record.user_value};"
          end
        end
      end

      lines.join("\n")
    end

    private

    attr_reader :cave_submissions, :form_data

    # Memoized [{ submission:, document_name:, records: }] across all submissions.
    def submission_diffs
      @submission_diffs ||= begin
        user_entries = collect_user_entries
        type_index = Hash.new(0)

        cave_submissions.filter_map do |submission|
          ocr = parse_ocr(submission)
          document_type = FieldCatalog.for_ocr_payload(ocr)
          next unless document_type

          artifact_key = document_type[:artifact_key]
          index = type_index[artifact_key]
          type_index[artifact_key] += 1
          user_entry = user_entries[artifact_key][index] || {}

          {
            submission:,
            document_name: document_type[:document_name],
            records: diff_fields(document_type, ocr, user_entry)
          }
        end
      end
    end

    def diff_fields(document_type, ocr, user_entry)
      document_type[:fields].filter_map do |field|
        ocr_raw = ocr[field.ocr_key]
        # A missing camel_key and an explicit nil both read as nil and canonicalize
        # to '' (treated as "no user value"). The frontend includes every catalog key.
        user_value = user_entry[field.camel_key]
        next if ValueNormalizer.canonical(field.type, ocr_raw) == ValueNormalizer.canonical(field.type, user_value)

        Record.new(
          document_name: document_type[:document_name],
          field: field.ocr_key,
          label: field.label,
          ocr_value: ocr_display(ocr_raw),
          user_value: user_display(field.type, user_value)
        )
      end
    end

    # Flattens files[].idpArtifacts into { 'dd214' => [entry, ...], 'deathCertificates' => [...] }.
    def collect_user_entries
      entries = Hash.new { |hash, key| hash[key] = [] }
      files = form_data['files'] || form_data[:files] || []

      Array(files).each do |file|
        artifacts = file['idpArtifacts'] || file[:idpArtifacts] || {}
        FieldCatalog::DOCUMENT_TYPES.each do |document_type|
          key = document_type[:artifact_key]
          list = artifacts[key] || artifacts[key.to_sym] || []
          entries[key].concat(Array(list))
        end
      end

      entries
    end

    def parse_ocr(submission)
      submission.parsed_response
    rescue JSON::ParserError, TypeError
      {}
    end

    def ocr_display(raw)
      value = raw.to_s.strip
      value.empty? ? EMPTY_DISPLAY : value
    end

    def user_display(type, value)
      rendered = ValueNormalizer.display(type, value).to_s.strip
      rendered.empty? ? EMPTY_DISPLAY : rendered
    end
  end
end
