# frozen_string_literal: true

module IvcChampva
  module ClaimsAttachmentIds
    ##
    # Builds the attachment_ids array for 10-7959A submissions.
    # For resubmissions:
    #  - If DTA applies (has_claim_docs == false): all documents labeled "Duty to Assist"
    #  - If Control number selected: the main claim sheet is labeled "CVA Reopen",
    #    supporting docs retain original types.
    #  - If PDI selected: all documents labeled "CVA Bene Response".
    # For all other cases, uses the standard logic.
    #
    # @param base_form_id [String] The mapped form ID (e.g., 'vha_10_7959a')
    # @param parsed_form_data [Hash] complete form submission data object
    # @param applicant_rounded_number [Integer] number of main form attachments needed
    # @return [Array<String>] array of attachment_ids for all documents
    def build_attachment_ids(base_form_id, parsed_form_data, applicant_rounded_number)
      Datadog::Tracing.trace('IVC Champva Forms - Build Attachment IDs') do
        if dta_applies?(parsed_form_data)
          build_dta_attachment_ids(parsed_form_data, applicant_rounded_number)
        elsif parsed_form_data['claim_status'] == 'resubmission'
          selector = parsed_form_data['pdi_or_claim_number']

          if selector == 'Control number'
            main = Array.new(applicant_rounded_number) { 'CVA Reopen' }
            main.concat(supporting_document_ids(parsed_form_data))
          elsif selector == 'PDI number'
            build_pdi_resubmission_attachment_ids(parsed_form_data, applicant_rounded_number)
          else
            build_default_attachment_ids(base_form_id, parsed_form_data, applicant_rounded_number)
          end
        else
          build_default_attachment_ids(base_form_id, parsed_form_data, applicant_rounded_number)
        end
      end
    end

    private

    def dta_applies?(parsed_form_data)
      Flipper.enabled?(:champva_claims_duty_to_assist) &&
        parsed_form_data['claim_status'] == 'resubmission' &&
        parsed_form_data['has_claim_docs'] == false
    end

    def build_dta_attachment_ids(parsed_form_data, applicant_rounded_number)
      supporting_doc_count = parsed_form_data['supporting_docs']&.count.to_i
      total_doc_count = applicant_rounded_number + supporting_doc_count
      Array.new(total_doc_count) { 'Duty to Assist' }
    end

    def build_pdi_resubmission_attachment_ids(parsed_form_data, applicant_rounded_number)
      supporting_doc_count = parsed_form_data['supporting_docs']&.count.to_i
      total_doc_count = applicant_rounded_number + supporting_doc_count
      Array.new(total_doc_count) { 'CVA Bene Response' }
    end
  end
end
