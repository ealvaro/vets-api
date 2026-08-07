# frozen_string_literal: true

require 'pdf_utilities/pdf_stamper'

module Pensions
  # @see ::VeteranFacingServices::NotificationCallback::SavedClaim
  class PDFStamper < ::PDFUtilities::PDFStamper
    # #
    # defined stamp sets to be used
    # override `timestamp` when calling `run` with the claim/attachment `created_at`
    #
    # TODO: Revert to static configuration after V2 migration complete
    # TODO: Update xy coordinates for V2 PDF (see Burials::PdfStamper)
    #
    # rubocop:disable Metrics/MethodLength
    def self.stamp_sets
      if Pensions.use_v2?
        fdc_y = 825
        page_number = 7
      else
        fdc_y = 820
        page_number = 0
      end
      {
        pensions_received_at: [{
          text: 'VA.GOV',
          timestamp: nil,
          x: 5,
          y: 5
        }],
        pensions_generated_claim: [{
          text: 'VA.GOV',
          timestamp: nil,
          x: 5,
          y: 5
        }, {
          text: 'FDC Reviewed - VA.gov Submission',
          timestamp: nil,
          x: 430,
          y: fdc_y,
          text_only: true
        }, {
          text: 'Application Submitted on va.gov',
          x: 440,
          y: 745,
          text_only: true, # passing as text only because we override how the date is stamped in this instance
          timestamp: nil,
          page_number:,
          size: 9,
          template: Pensions.pdf_path,
          multistamp: true
        }]
      }
    end
    # rubocop:enable Metrics/MethodLength
  end
end
