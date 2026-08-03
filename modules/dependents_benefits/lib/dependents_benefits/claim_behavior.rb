# frozen_string_literal: true

require 'dependents_benefits/claim_behavior/submission_status'
require 'dependents_benefits/claim_behavior/form_validation'
require 'dependents_benefits/claim_behavior/form_type_checking'
require 'dependents_benefits/claim_behavior/veteran_information'

module DependentsBenefits
  ##
  # Shared validation and schema logic for DependentsBenefits claims
  # Include in SavedClaim subclasses that handle dependents benefits forms
  #
  module ClaimBehavior
    extend ActiveSupport::Concern

    include SubmissionStatus
    include FormValidation
    include FormTypeChecking
    include VeteranInformation

    # Generates a PDF representation of the claim form
    #
    # @param file_name [String, nil] Optional custom filename for the generated PDF
    # @param fill_options [Hash] Additional options for PDF generation
    # @param kwargs [Hash] Keyword arguments (form_id, student, created_at, etc.)
    # @return [String] Path to the generated PDF file
    def to_pdf(file_name = nil, fill_options = {}, **kwargs)
      if Flipper.enabled?(:enable_686_674_digital_pdf)
        monitor.track_info_event("Generating dPDF: #{self.class.name} #{id}", action: 'dpdf.generate')
        # Future PR: call out to digital PDF service when it is ready
      else
        options = fill_options.merge(kwargs)
        actual_file_name = kwargs.any? ? id.to_s : file_name
        DependentsBenefits::PdfFill::Filler.fill_form(self, actual_file_name, options)
      end
    end

    # adds a signature date attribute into the parsed form for FDF
    def add_signature_date
      parsed_form.merge!({ 'signatureDate' => created_at.strftime('%Y-%m-%d') })
    end

    # retrieve the parent_claim_id for _this_ claim
    def parent_claim_id
      child_of_groups&.last&.parent_claim_id
    end

    # Format the claim data for submission to FDF
    # TODO: refactor so this is no longer needed after FDF pilot; future
    def fdf_submission_payload
      add_signature_date
      payload = parsed_form.deep_dup
      dependents_app = payload.delete('dependents_application') || {}

      payload = payload.deep_merge(dependents_app) # combine nested hashes
      deep_camelize_keys(payload) # convert snake_case to camelCase
    end

    private

    # Returns a memoized instance of the DependentsBenefits monitor
    #
    # @return [DependentsBenefits::Monitor] Monitor instance for tracking events and errors
    def monitor
      @monitor ||= DependentsBenefits::Monitor.new
    end

    # Override base class (::SavedClaim) implementation since these classes
    # have their own pdf filler logic
    def pdf_overflow_tracking
      tags = ["form_id:#{form_id}", "doctype:#{document_type}"]

      filename = to_pdf

      # @see PdfFill::Filler
      StatsD.increment('saved_claim.pdf.overflow', tags:) if filename.end_with?('_final.pdf')
    rescue => e
      Rails.logger.warn("#{self.class} Error tracking PDF overflow", form_id:, saved_claim_id: id, error: e)
    ensure
      Common::FileHelpers.delete_file_if_exists(filename)
    end
  end
end
