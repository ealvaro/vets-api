# frozen_string_literal: true

module ClaimsEvidence
  # The VBMS document types a Veteran may file Supplemental Claim evidence under, keyed by the
  # documentTypeId Claims Evidence expects in providerData.
  #
  # If this list is updated, vets-website's SUPPLEMENTAL_CLAIM_DOC_TYPES_FALLBACK should be updated
  # too.
  module DocumentType
    module_function

    # @param id [Integer] documentTypeId
    def supported?(id)
      TYPES.key?(id)
    end

    # @param id [Integer] documentTypeId
    # @return [String, nil] the VBMS label, or nil for an id we do not accept
    def label(id)
      TYPES[id]
    end

    TYPES = {
      26 => 'Buddy/Lay Statement',
      29 => 'Civilian Police Reports',
      34 => 'Correspondence',
      40 => 'Certificate of Release or Discharge From Active Duty (DD214)',
      45 => 'Military Personnel Record',
      58 => 'Medical Treatment Record - Government Facility',
      59 => 'Medical Treatment Record - Non-Government Facility',
      80 => 'Photographs',
      111 => 'VA Form 21-2680',
      116 => 'VA Form 21-4142',
      124 => 'VA Form 21-4192',
      126 => 'VA Form 21-4502',
      142 => 'VA Form 21-674 (Report of School Attendance)',
      148 => 'VA Form 21-686c',
      158 => 'VA Form 21-8940',
      168 => 'VA Form 26-4555',
      375 => 'VA Form 21-0779',
      381 => 'VA Form 21-0781',
      382 => 'VA Form 21-0781a',
      478 => 'Medical Treatment Records - Furnished by SSA',
      702 => 'Disability Benefits Questionnaire (DBQ) - Veteran Provided',
      703 => 'Goldmann Perimetry Chart/Field of Vision Chart',
      827 => 'VA Form 21-4142a'
    }.freeze
    private_constant :TYPES
  end
end
