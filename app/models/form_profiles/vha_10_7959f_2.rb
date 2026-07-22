# frozen_string_literal: true

class FormProfiles::VHA107959f2 < FormProfile
  FORM_ID = '10-7959F-2'

  def metadata
    {
      version: 0,
      prefill: prefill_enabled?,
      returnUrl: '/personal-information'
    }
  end

  def prefill_enabled?
    Flipper.enabled?(:form_107959f2_prefill_enabled, user)
  end

  def prefill
    return { form_data: {}, metadata: } unless prefill_enabled?

    super
  end
end
