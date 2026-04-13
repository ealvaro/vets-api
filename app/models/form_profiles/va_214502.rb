# frozen_string_literal: true

# FormProfile for VA Form 21-4502
class FormProfiles::VA214502 < FormProfile
  def metadata
    {
      version: 0,
      prefill: false,
      returnUrl: '/eligibility'
    }
  end
end
