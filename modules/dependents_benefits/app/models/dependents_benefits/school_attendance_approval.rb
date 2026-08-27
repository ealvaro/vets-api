# frozen_string_literal: true

require 'dependents_benefits/claim_behavior'

module DependentsBenefits
  # DependentsBenefit 21-674 Active::Record
  # @see app/model/saved_claim
  class SchoolAttendanceApproval < ::SavedClaim
    include DependentsBenefits::ClaimBehavior

    # DependentsBenefit Form ID
    FORM = DependentsBenefits::SCHOOL_ATTENDANCE_APPROVAL

    # Returns the business line associated with this process
    #
    # @return [String]
    def business_line
      'CMP'
    end

    # the VBMS document type for _this_ claim type
    def document_type
      142
    end

    ##
    # Check if feature enabled to track pdf overflow for claim submissions
    #
    # @return [Boolean]
    def track_pdf_overflow?
      Flipper.enabled?(:saved_claim_pdf_overflow_tracking) || false
    end
  end
end
