# frozen_string_literal: true

require 'pdf_utilities/pdf_stamper'

module DependentsBenefits
  # @see ::PDFUtilities::PDFStamper
  class PdfStamper < ::PDFUtilities::PDFStamper
    # defined stamp sets to be used
    # override `timestamp` when calling `run` with the claim/attachment `created_at`
    STAMP_SETS = {
      dependents_benefits_received_at: [{
        text: 'VA.GOV',
        timestamp: nil,
        x: 5,
        y: 5
      }],
      dependents_benefits_21_686C_generated_claim: [{
        text: 'Application Submitted on va.gov',
        x: 440,
        y: 745,
        text_only: true, # passing as text only because we override how the date is stamped in this instance
        timestamp: nil,
        page_number: 6,
        size: 9,
        template: DependentsBenefits::PDF_PATH_21_686C,
        multistamp: true
      }],
      dependents_benefits_21_674_generated_claim: [{
        text: 'Application Submitted on va.gov',
        x: 440,
        y: 745,
        text_only: true, # passing as text only because we override how the date is stamped in this instance
        timestamp: nil,
        size: 9,
        template: DependentsBenefits::PDF_PATH_21_674,
        multistamp: true
      }]
    }.freeze

    # return the stamp key for a specific form id
    #
    # @param form_id [String] the form id - eg. 21-686c, 21-674
    # @return [Symbol] a key within STAMP_SETS
    def self.form_stamp_set(form_id)
      "dependents_benefits_#{form_id.upcase}_generated_claim".tr('-', '_').to_sym
    end
  end
end
