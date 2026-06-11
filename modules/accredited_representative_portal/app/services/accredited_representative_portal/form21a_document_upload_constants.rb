# frozen_string_literal: true

module AccreditedRepresentativePortal
  module Form21aDocumentUploadConstants
    # File type codes expected by GCLAWS Document API
    FILE_TYPES = {
      'application/pdf' => 7,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 15
    }.freeze

    # Maps form_data document keys to GCLAWS document type codes.
    # The keys are derived from details_slug: "conviction-details" -> "convictionDetailsDocuments".
    # Values confirmed with the GCLAWS team.
    # 1 is jurisdiction, 2 is agency, so document types start at 3 to avoid overlap
    # 16 is conditionThatAffectsExaminationDetailsDocuments which hasn't been added yet

    DOCUMENT_TYPES = {
      'convictionDetailsDocuments' => 3,
      'courtMartialedDetailsDocuments' => 4,
      'underChargesDetailsDocuments' => 5,
      'resignedFromEducationDetailsDocuments' => 6,
      'withdrawnFromEducationDetailsDocuments' => 7,
      'disciplinedForDishonestyDetailsDocuments' => 8,
      'resignedForDishonestyDetailsDocuments' => 9,
      'representativeForAgencyDetailsDocuments' => 10,
      'reprimandedInAgencyDetailsDocuments' => 11,
      'resignedFromAgencyDetailsDocuments' => 12,
      'appliedForVaAccreditationDetailsDocuments' => 13,
      'terminatedByVsorgDetailsDocuments' => 14,
      'conditionThatAffectsRepresentationDetailsDocuments' => 15
    }.freeze

    # Returns the GCLAWS file type code for a given content type
    # @param content_type [String] MIME type (e.g., "application/pdf")
    # @return [Integer, nil] GCLAWS file type code (1=PDF, 2=DOCX) or nil if unknown
    def self.file_type_for(content_type)
      FILE_TYPES[content_type]
    end

    # Returns the GCLAWS document type code for a given form_data key
    # @param documents_key [String] The key from form_data (e.g., "convictionDetailsDocuments")
    # @return [Integer, nil] GCLAWS document type code or nil if unknown
    def self.document_type_for(documents_key)
      DOCUMENT_TYPES[documents_key]
    end
  end
end
