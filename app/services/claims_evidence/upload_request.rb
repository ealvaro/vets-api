# frozen_string_literal: true

module ClaimsEvidence
  # The details of one file being uploaded. Filled in once, after the request is validated,
  # so the duplicate check and the upload always use the same values.
  UploadRequest = Data.define(:file, :doc_type_id, :sc_id, :file_name, :file_size) do
    def document_type
      ClaimsEvidence::DocumentType.label(doc_type_id)
    end
  end
end
