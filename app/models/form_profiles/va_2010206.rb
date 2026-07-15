# frozen_string_literal: true

class FormProfiles::VA2010206 < FormProfile
  def metadata
    {
      version: 0,
      prefill: true,
      returnUrl: '/preparer-type'
    }
  end
end
