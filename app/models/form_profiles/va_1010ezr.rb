# frozen_string_literal: true

require 'hca/enrollment_eligibility/service'
require 'logging/helper/data_scrubber'

class FormProfiles::VA1010ezr < FormProfile
  def metadata
    {
      version: 0,
      prefill: true,
      returnUrl: '/veteran-information/personal-information'
    }
  end

  def ezr_data
    @ezr_data ||=
      begin
        HCA::EnrollmentEligibility::Service.new.get_ezr_data(user, @military_information)
      rescue => e
        Rails.logger.error(scrub_pii(e.message))
        OpenStruct.new
      end
  end

  def clean!(hash)
    hash.deep_transform_keys! { |k| k.camelize(:lower) }
    Common::HashHelpers.deep_compact(hash)
  end

  private

  def scrub_pii(message)
    Logging::Helper::DataScrubber.scrub(message)
  end
end
