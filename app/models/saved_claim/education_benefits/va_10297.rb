# frozen_string_literal: true

class SavedClaim::EducationBenefits::VA10297 < SavedClaim::EducationBenefits
  add_form_and_validation('22-10297')

  def after_submit(_user)
    return unless Flipper.enabled?(:form22_10297_confirmation_email)

    parsed_form_data = JSON.parse(form)
    email = parsed_form_data.dig('contactInfo', 'emailAddress')

    return if email.blank?

    send_confirmation_email(parsed_form_data, email)
  end

  def retention_period
    60.days
  end

  private

  def send_confirmation_email(parsed_form_data, email)
    if Flipper.enabled?(:form10297_confirmation_email_with_silent_failure_processing)
      # this method is in the parent class
      send_education_benefits_confirmation_email(email, parsed_form, {})
    else
      personalisation = {
        'first_name' => parsed_form_data.dig('applicantFullName', 'first')&.upcase.presence,
        'date_submitted' => Time.zone.today.strftime('%B %d, %Y'),
        'confirmation_number' => education_benefits_claim.confirmation_number,
        'regional_office_address' => regional_office_address
      }

      api_key_path = 'Settings.vanotify.services.va_gov.api_key'
      VANotify::V2::QueueEmailJob.enqueue(email, template_id, personalisation, api_key_path)
    end
  end

  def template_id
    Settings.vanotify.services.va_gov.template_id.form10297_confirmation_email
  end
end
