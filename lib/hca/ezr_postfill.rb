# frozen_string_literal: true

require 'hca/enrollment_eligibility/service'

module HCA
  module EzrPostfill
    module_function

    def post_fill_hash(user)
      raise Common::Exceptions::ParameterMissing, 'icn' if user.icn.blank?

      ee_facility = HCA::EnrollmentEligibility::Service.new.lookup_user(user.icn)[:preferred_facility]

      {
        'isEssentialAcaCoverage' => false,
        'vaMedicalFacility' => ee_facility&.split&.first
      }
    end
  end
end
