# frozen_string_literal: true

module IvcChampva
  # Expects including class to define: form_id, uuid, data, metadata
  module DataTransformations
    def transliterated_data
      @transliterated_data ||= begin
        copy = data.deep_dup
        IvcChampva::FormFieldTransliterator.transliterate_all!(copy)
        copy.freeze
      end
    end

    def validated_metadata
      @validated_metadata ||= IvcChampva::MetadataValidator.validate(metadata.deep_dup).freeze
    end

    ##
    # Creates a modified metadata hash to be attached to individual files upon upload to S3.
    # When additional_file_metadata is present and a file_path is provided, merges any
    # file-specific metadata overrides for the current file.
    #
    # @param full_metadata [Hash] The complete validated metadata hash (including attachment_ids, etc.)
    # @param attachment_id [Integer, String] Either a number or a string describing the file,
    #   e.g., 'Social Security card'
    # @param file_path [String, nil] Optional file path for per-file metadata lookup
    #
    # @return [Hash] modified metadata object suitable for S3 upload
    def self.metadata_for_s3(full_metadata, attachment_id, file_path = nil)
      key = attachment_id.is_a?(Integer) ? 'claim_id' : 'attachment_id'
      result = full_metadata
               .except('primaryContactInfo', 'attachment_ids', 'supportingDocApplicants', 'additional_file_metadata')
               .merge({ key => attachment_id.to_s })

      if file_path && full_metadata['additional_file_metadata']
        file_name = File.basename(file_path).gsub('-tmp', '')
        file_overrides = full_metadata['additional_file_metadata'][file_name]
        result.merge!(file_overrides) if file_overrides
      end

      result
    end

    ##
    # Resolves supporting document attachment IDs from persistent attachment records,
    # sorted by upload order.
    #
    # @return [Array<String>] Sorted array of attachment ID strings
    def supporting_document_ids
      cached_uploads = []
      supporting_docs = data['supporting_docs']
      supporting_docs&.each_with_index do |d, index|
        record = PersistentAttachments::MilitaryRecords.find_by(guid: d['confirmation_code'])
        cached_uploads.push({ attachment_id: d['attachment_id'],
                              created_at: record.created_at,
                              file_name: record.file.id,
                              index: })
      end

      ohi_supporting_documents_present = supporting_docs&.any? do |doc|
        doc['attachment_id'].in?(IvcChampva::Constants::OHI_ATTACHMENT_IDS)
      end

      sorted_uploads = if Flipper.enabled?(:champva_supporting_docs_ordering) && ohi_supporting_documents_present
                         cached_uploads.sort_by { |h| [h[:created_at], h[:index]] }
                       else
                         cached_uploads.sort_by { |h| h[:created_at] }
                       end
      attachment_ids = sorted_uploads.pluck(:attachment_id)&.compact.presence

      attachment_ids || supporting_docs&.pluck('attachment_id')&.compact.presence ||
        supporting_docs&.pluck('claim_id')&.compact.presence || []
    end

    ##
    # Computes the number of main-form PDF pages based on the form's ADDITIONAL_PDF_COUNT
    # and ADDITIONAL_PDF_KEY constants.
    #
    # @return [Integer] The number of main-form attachment slots (always >= 1)
    def applicant_pdf_count
      form_class = self.class
      additional_pdf_count = form_class.const_defined?(:ADDITIONAL_PDF_COUNT) ? form_class::ADDITIONAL_PDF_COUNT : 1
      applicant_key = form_class.const_defined?(:ADDITIONAL_PDF_KEY) ? form_class::ADDITIONAL_PDF_KEY : 'applicants'

      applicants_count = data[applicant_key]&.count.to_i
      total_applicants_count = applicants_count.to_f / additional_pdf_count
      total_applicants_count.ceil.zero? ? 1 : total_applicants_count.ceil
    end

    ##
    # Builds the attachment_ids array using the standard logic: main form PDFs
    # labeled with the form_id, followed by supporting document IDs.
    # Subclasses may override this to provide form-specific attachment ID logic.
    #
    # @param base_form_id [String] The base form ID (e.g., 'vha_10_10d')
    # @param applicant_rounded_number [Integer] Number of main form attachment slots
    # @return [Array<String>] Array of attachment_ids for all documents
    def build_attachment_ids(base_form_id, applicant_rounded_number)
      Datadog::Tracing.trace('IVC Champva Forms - Build Attachment IDs') do
        build_default_attachment_ids(base_form_id, applicant_rounded_number)
      end
    end

    ##
    # Builds the default attachment_ids array using the standard logic.
    #
    # @param base_form_id [String] The mapped form ID
    # @param applicant_rounded_number [Integer] Number of main form attachment slots
    # @return [Array<String>] Array of attachment_ids
    def build_default_attachment_ids(base_form_id, applicant_rounded_number)
      attachment_ids = Array.new(applicant_rounded_number) { base_form_id }
      attachment_ids.concat(supporting_document_ids)
    end

    ##
    # Creates a stamped blank page and returns file info directly,
    # bypassing the supporting_docs pipeline so the page gets named form_page
    # instead of supporting_doc-N (which would inflate the confirmation email count).
    #
    # @return [Hash, nil] { file_path:, attachment_id: } or nil when not applicable
    def build_stamped_page
      Datadog::Tracing.trace('IVC Champva Forms - Build Stamped Page') do
        return unless methods.include?(:stamp_metadata)

        stamps = stamp_metadata
        return if stamps.nil? || !stamps.is_a?(Hash)

        blank_page_path = IvcChampva::Attachments.get_blank_page
        IvcChampva::PdfStamper.stamp_metadata_items(blank_page_path, stamps[:metadata])

        legacy_form_id = IvcChampva::FormVersionManager.get_legacy_form_id(form_id)
        stamped_name = "#{uuid}_#{legacy_form_id}_form_page.pdf"
        stamped_path = File.join('tmp', stamped_name)
        FileUtils.mv(blank_page_path, stamped_path)

        { file_path: stamped_path, attachment_id: stamps[:attachment_id] }
      end
    end

    ##
    # High-level method that computes attachment IDs and builds stamped pages.
    # Consolidates the logic previously in UploadsController#get_attachment_ids_and_form.
    #
    # @param base_form_id [String] The base (unmapped) form ID
    # @param current_user [Object] The current user (for feature flags)
    # @return [Array(Array<String>, Hash)] [attachment_ids, stamped_page_or_nil]
    def prepare_submission_data(base_form_id, current_user)
      rounded_count = applicant_pdf_count
      stamped_page = build_stamped_page if Flipper.enabled?(:champva_claims_duty_to_assist, current_user)

      attachment_ids = build_attachment_ids(base_form_id, rounded_count)
      attachment_ids = [base_form_id] if attachment_ids.empty?

      [attachment_ids.compact, stamped_page]
    end
  end
end
