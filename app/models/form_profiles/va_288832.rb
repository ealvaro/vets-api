# frozen_string_literal: true

class FormProfiles::VA288832 < FormProfile
  def self.form_filename_and_version(form_id, current_user)
    if Flipper.enabled?(:chapter_36_form_rebuild_cveteam, current_user)
      ["#{form_id}v2", 2]
    else
      [form_id, 1]
    end
  end

  def prefill
    return { metadata: } unless FormProfile.prefill_enabled_forms.include?(form_id)

    @identity_information = initialize_identity_information
    @military_information = initialize_military_information
    @contact_information = initialize_contact_information

    versioned_form_id, version_number = self.class.form_filename_and_version(form_id, @user)

    mappings = self.class.mappings_for_form(versioned_form_id)
    form_data = generate_prefill(mappings)
    form_data['version'] = version_number if version_number > 1

    { form_data:, metadata: }
  end

  def metadata
    {
      version: 0,
      prefill: true,
      returnUrl: '/claimant-information'
    }
  end
end
