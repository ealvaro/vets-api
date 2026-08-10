# frozen_string_literal: true

require 'common/file_helpers'
require 'survivors_benefits/benefits_intake/submit_claim_job'
require 'survivors_benefits/custodian_addendum'
require 'survivors_benefits/helpers'
require 'pdf_fill/filler'
require 'pdf_fill/forms/va214138'

module SurvivorsBenefits
  ##
  # SurvivorsBenefits 21P-534EZ Active::Record
  # @see app/model/saved_claim
  #
  class SavedClaim < ::SavedClaim
    # Survivors Benefits Form ID
    FORM = SurvivorsBenefits::FORM_ID

    # the predefined regional office address
    #
    # @return [Array<String>] the address lines of the regional office
    def regional_office
      ['Department of Veteran\'s Affairs',
       'Pension Intake Center',
       'P.O. Box 5365',
       'Janesville, Wisconsin 53547-5365']
    end

    ##
    # Returns the business line associated with this process
    #
    # @return [String]
    def business_line
      'NCA'
    end

    # the VBMS document type for _this_ claim type
    def document_type
      1292
    end

    # Utility function to retrieve claimant email from form
    #
    # @return [String] the claimant email
    def email
      parsed_form['email'] || 'test@example.com' # TODO: update this when we have a real email field
    end

    # Utility function to retrieve veteran first name from form
    #
    # @return [String]
    def veteran_first_name
      parsed_form.dig('veteranFullName', 'first')
    end

    # Utility function to retrieve veteran last name from form
    #
    # @return [String]
    def veteran_last_name
      parsed_form.dig('veteranFullName', 'last')
    end

    # Utility function to retrieve claimant first name from form
    #
    # @return [String]
    def claimant_first_name
      parsed_form.dig('claimantFullName', 'first')
    end

    ##
    # claim attachment list
    #
    # @see PersistentAttachment
    #
    # @return [Array<String>] list of attachments
    #
    def attachment_keys
      [:files].freeze
    end

    # Run after a claim is saved, this processes any files and workflows that are present
    # and sends them to our internal partners for processing.
    # Only removed Sidekiq call from super
    def process_attachments!
      refs = attachment_keys.map { |key| Array(open_struct_form.send(key)) }.flatten
      files = PersistentAttachment.where(guid: refs.map(&:confirmationCode))
      files.find_each { |f| f.update(saved_claim_id: id) }

      artifacts = Array(refs).flat_map { |r| Array(r.idpArtifacts) }
      cave_submission_ids = artifacts.flat_map { |a| Array(a.caveSubmissionIds) }.compact.uniq
      return if cave_submission_ids.blank?

      # rubocop:disable Rails/SkipsModelValidations -- reviewer confirmed no callbacks or validations on CaveSubmission
      CaveSubmission.where(id: cave_submission_ids).update_all(saved_claim_id: id)
      # rubocop:enable Rails/SkipsModelValidations
    end

    def filler
      ::PdfFill::Filler
    end

    ##
    # Generates a PDF from the saved claim data
    #
    # @param file_name [String, nil] Optional name for the output PDF file
    # @param fill_options [Hash] Additional options for PDF generation
    # @return [String] Path to the generated PDF file
    #
    def to_pdf(file_name = nil, fill_options = {})
      pdf_path = filler.fill_form(self, file_name, fill_options)
      return unless pdf_path

      form_data = form.present? ? parsed_form : {}

      if cave_submissions.exists? || custodian_filing?(form_data)
        statement_pdf_path = fill_ancillary_pdf(form_data)

        folder = 'tmp/pdfs'
        FileUtils.mkdir_p(folder)
        combined_file_path = "#{folder}/#{SurvivorsBenefits::FORM_ID}_#{guid}_combined.pdf"
        filler.merge_pdfs(pdf_path, statement_pdf_path, combined_file_path)

        SurvivorsBenefits::PdfFill::Va21p534ez.stamp_signature(combined_file_path, form_data)
      else
        SurvivorsBenefits::PdfFill::Va21p534ez.stamp_signature(pdf_path, form_data)
      end
    end

    ##
    # Generates the completed-form PDF as it is submitted downstream: redesigned extras, the shared
    # machinery's built-in footers suppressed, and the submission date/timestamp/authentication
    # watermark stamped on the bottom-right of every page. Every rendition of the completed form (the
    # Benefits Intake upload and the S3 copy behind the confirmation-page download link) must carry the
    # same watermark, so both are generated through here.
    #
    # @param file_name [String, nil] Optional name for the output PDF file
    # @return [String, nil] Path to the stamped PDF file (nil when the fill produced no PDF)
    #
    def to_stamped_pdf(file_name = nil)
      raw_pdf = to_pdf(file_name, extras_redesign: true, omit_esign_stamp: true, omit_footer: true)
      return raw_pdf if raw_pdf.blank?

      stamped_pdf = SurvivorsBenefits::PdfFill::Va21p534ez.stamp_submission_footer(raw_pdf, created_at)
      # stamp_submission_footer fails open and returns raw_pdf on error; only remove the
      # intermediate when a new stamped copy replaced it.
      Common::FileHelpers.delete_file_if_exists(raw_pdf) unless stamped_pdf == raw_pdf
      stamped_pdf
    end

    ##
    # Fills a Form 21-4138 with the raw JSON from CAVE if the Claim has a CaveSubmission
    # Whether a custodian is filing this claim on behalf of a child under 18. Such claims get a
    # 21-4138 addendum even without a CaveSubmission, because the custodian's relationship to the
    # child, address, and email have nowhere to go on the 21P-534EZ itself.
    #
    # @param form_data [Hash] the parsed claim form
    # @return [Boolean]
    def custodian_filing?(form_data)
      SurvivorsBenefits::Helpers.custodian_filing?(form_data['claimantRelationship'])
    end

    ##
    # Fills a Form 21-4138 addendum, documenting the custodian filing on a child's behalf and/or
    # the fields a user corrected on CAVE-extracted documents.
    #
    def fill_ancillary_pdf(form_data)
      result = ::PdfFill::Forms::Va214138::PdfSchema.call(
        {
          claimantFullName: form_data['claimantFullName'] || form_data['veteranFullName'],
          veteranSocialSecurityNumber: form_data['veteranSocialSecurityNumber'],
          vaFileNumber: form_data['vaFileNumber'],
          veteranDateOfBirth: form_data['veteranDateOfBirth'],
          veteranServiceNumber: form_data['veteranServiceNumber'],
          claimantPhone: claimant_phone(form_data),
          claimantInternationalPhone: claimant_international_phone(form_data),
          claimantEmailAddress: form_data['claimantEmail'] || form_data['veteranEmail'] || form_data['email'],
          claimantAddress: form_data['claimantAddress'] || form_data['veteranAddress'],
          remarks: ancillary_remarks(form_data)
        }
      )
      filler.fill_ancillary_form(result.to_h, id, '21-4138', { extras_redesign: true })
    end

    ##
    # Composes the 21-4138 Remarks from the custodian block and the CAVE change log, in that
    # order. Either may be absent, but the caller only reaches here when at least one applies, so
    # the result satisfies the PdfSchema's `required(:remarks).filled(:string)`.
    #
    # cave_change_log_remarks is skipped entirely when there are no CaveSubmissions — it persists
    # the change log and forwards corrections to CAVE as side effects.
    #
    # @param form_data [Hash] the parsed claim form
    # @return [String]
    def ancillary_remarks(form_data)
      [
        SurvivorsBenefits::CustodianAddendum.remarks(form_data),
        (cave_change_log_remarks(form_data) if cave_submissions.exists?)
      ].compact_blank.join("\n\n")
    end

    ##
    # Digs out the claimant's phone number
    #
    def claimant_phone(form_data)
      if form_data['primaryPhone'].is_a?(Hash) && form_data['primaryPhone']['countryCode'] == 'US'
        form_data['primaryPhone']['contact']
      else
        form_data['claimantPhone'] || form_data['veteranPhone']
      end
    end

    ##
    # Digs out the claimant's international phone number
    #
    def claimant_international_phone(form_data)
      if form_data['primaryPhone'].is_a?(Hash) && !form_data['primaryPhone']['countryCode'] == 'US'
        form_data['primaryPhone']['contact']
      else
        form_data['claimantInternationalPhone'] || form_data['veteranInternationalPhone']
      end
    end

    ##
    # Class name for notification email
    # @return [Class]
    def send_email(email_type)
      SurvivorsBenefits::NotificationEmail.new(id).deliver(email_type)
    end

    ##
    # Converts the form_data into json that can be read by the IBM - GOVCIO mms connection
    #
    def to_ibm
      service_class = if Flipper.enabled?(:survivors_benefits_form_2025_version_enabled)
                        SurvivorsBenefits::StructuredData::V2025::StructuredDataService
                      else
                        SurvivorsBenefits::StructuredData::V2022::StructuredDataService
                      end
      service_class.new(parsed_form).build_structured_data
    rescue => e
      Rails.logger.error("Error building structured data for IBM submission: #{e.message}")
      nil
    end
  end
end
