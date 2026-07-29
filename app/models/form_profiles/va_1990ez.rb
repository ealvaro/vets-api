# frozen_string_literal: true

class FormProfiles::VA1990ez < FormProfile
  def return_url
    '/benefit-selection'
  end

  def metadata
    {
      version: 0,
      prefill: true,
      returnUrl: return_url
    }
  end
end
