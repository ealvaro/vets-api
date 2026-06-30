# frozen_string_literal: true

module Cave
  # Canonical catalog of the CAVE-extracted artifact fields, owned by vets-api.
  #
  # For each supported document type it maps:
  #   * ocr_key   - the SCREAMING_SNAKE key as it appears in CaveSubmission#cave_response
  #                 (the raw OCR payload produced by the CAVE engine)
  #   * camel_key - the key as it appears in the user-final files[].idpArtifacts entry
  #                 submitted by vets-website (post-normalization)
  #   * label     - the human-readable label shown on the generated 21-4138 change log
  #   * type      - drives comparison/formatting (see Cave::ValueNormalizer)
  #
  # Labels and document names mirror vets-website
  # (src/applications/survivors-benefits/cave/fieldMapping.js and the artifact
  # transformers). Keep in sync if the frontend labels change.
  module FieldCatalog
    Field = Struct.new(:ocr_key, :camel_key, :label, :type, keyword_init: true)

    DD214 = {
      artifact_key: 'dd214',
      document_name: 'DD-214',
      fields: [
        Field.new(ocr_key: 'VETERAN_NAME', camel_key: 'veteranName', label: 'Veteran name', type: :name),
        Field.new(ocr_key: 'VETERAN_SSN', camel_key: 'veteranSsn', label: 'Social Security number', type: :ssn),
        Field.new(ocr_key: 'VETERAN_DOB', camel_key: 'veteranDob', label: 'Date of birth', type: :date),
        Field.new(ocr_key: 'BRANCH_OF_SERVICE', camel_key: 'branchOfService', label: 'Branch of service',
                  type: :branch),
        Field.new(ocr_key: 'GRADE_RATE_RANK', camel_key: 'gradeRateRank', label: 'Grade, rate, or rank', type: :text),
        Field.new(ocr_key: 'PAY_GRADE', camel_key: 'payGrade', label: 'Pay grade', type: :pay_grade),
        Field.new(ocr_key: 'DATE_INDUCTED', camel_key: 'dateInducted', label: 'Date inducted', type: :date),
        Field.new(ocr_key: 'DATE_ENTERED_ACTIVE_SERVICE', camel_key: 'dateEnteredActiveService',
                  label: 'Date entered active service', type: :date),
        Field.new(ocr_key: 'DATE_SEPARATED_FROM_SERVICE', camel_key: 'dateSeparatedFromService',
                  label: 'Date separated from service', type: :date),
        Field.new(ocr_key: 'CAUSE_OF_SEPARATION', camel_key: 'causeOfSeparation', label: 'Cause of separation',
                  type: :text),
        Field.new(ocr_key: 'CHARACTER_OF_SERVICE', camel_key: 'characterOfService', label: 'Character of service',
                  type: :character_of_service),
        Field.new(ocr_key: 'SEPARATION_TYPE', camel_key: 'separationType', label: 'Separation type', type: :text),
        Field.new(ocr_key: 'SEPARATION_CODE', camel_key: 'separationCode', label: 'Separation code',
                  type: :separation_code)
      ].freeze
    }.freeze

    DEATH_CERTIFICATE = {
      artifact_key: 'deathCertificates',
      document_name: 'Death Certificate',
      fields: [
        Field.new(ocr_key: 'DECENDENT_FULL_NAME', camel_key: 'decendentFullName', label: 'Decedent name',
                  type: :name),
        Field.new(ocr_key: 'DECENDENT_SSN', camel_key: 'decendentSsn', label: 'Social Security number', type: :ssn),
        Field.new(ocr_key: 'DECENDENT_DATE_OF_DEATH', camel_key: 'decendentDateOfDeath', label: 'Date of death',
                  type: :date),
        Field.new(ocr_key: 'DECENDENT_DATE_OF_DISPOSITION', camel_key: 'decendentDateOfDisposition',
                  label: 'Date of disposition', type: :date),
        Field.new(ocr_key: 'CAUSE_OF_DEATH', camel_key: 'causeOfDeath', label: 'Cause of death', type: :text),
        Field.new(ocr_key: 'UNDERLYING_CAUSE_OF_DEATH_B', camel_key: 'underlyingCauseOfDeathB',
                  label: 'Underlying cause of death (line b)', type: :text),
        Field.new(ocr_key: 'UNDERLYING_CAUSE_OF_DEATH_C', camel_key: 'underlyingCauseOfDeathC',
                  label: 'Underlying cause of death (line c)', type: :text),
        Field.new(ocr_key: 'UNDERLYING_CAUSE_OF_DEATH_D', camel_key: 'underlyingCauseOfDeathD',
                  label: 'Underlying cause of death (line d)', type: :text),
        Field.new(ocr_key: 'MANNER_OF_DEATH', camel_key: 'mannerOfDeath', label: 'Manner of death', type: :text),
        Field.new(ocr_key: 'DECENDENT_MARITAL_STATUS', camel_key: 'decendentMaritalStatus', label: 'Marital status',
                  type: :text)
      ].freeze
    }.freeze

    DOCUMENT_TYPES = [DD214, DEATH_CERTIFICATE].freeze

    # Precomputed OCR-key set for O(1) membership in for_ocr_payload (DD214,
    # unlike death certificates, has no single unambiguous key prefix).
    DD214_OCR_KEYS = DD214[:fields].to_set(&:ocr_key).freeze

    module_function

    # Infers the document type for a raw OCR payload (CaveSubmission#cave_response)
    # by which catalog's OCR keys it carries. Death certificates are checked first
    # because their DECENDENT_* keys are unambiguous.
    def for_ocr_payload(ocr)
      keys = ocr.is_a?(Hash) ? ocr.keys.map(&:to_s) : []
      return DEATH_CERTIFICATE if keys.any? { |k| k.start_with?('DECENDENT_') }
      return DD214 if keys.any? { |k| DD214_OCR_KEYS.include?(k) }

      nil
    end

    def by_artifact_key(artifact_key)
      DOCUMENT_TYPES.find { |dt| dt[:artifact_key] == artifact_key.to_s }
    end
  end
end
