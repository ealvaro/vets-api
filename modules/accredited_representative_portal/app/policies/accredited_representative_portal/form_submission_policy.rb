# frozen_string_literal: true

require 'lighthouse/benefits_claims/service'

module AccreditedRepresentativePortal
  class FormSubmissionPolicy < ApplicationPolicy
    def dependents?
      claimant_representative.present?
    end

    def check_poa_status?
      claimant_representative.present?
    end

    private

    def claimant_representative
      ClaimantRepresentative.find(
        claimant_icn: @record,
        power_of_attorney_holder_memberships:
          @user.power_of_attorney_holder_memberships
      )
    rescue Common::Exceptions::RecordNotFound
      nil
    end
  end
end
