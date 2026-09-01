# frozen_string_literal: true

class SavedClaim::EducationBenefits::VA10272 < SavedClaim::EducationBenefits
  add_form_and_validation('22-10272')

  def requires_authenticated_user?
    true
  end

  def after_submit(user)
    associate_attachments!
    user_account_uuid = user&.user_account_uuid
    EducationForm::SubmitEducationBenefitsClaimJob.perform_async(id, user_account_uuid)
  end

  def attachment_keys
    [:supportingDocuments]
  end

  # Link uploaded files to this claim without enqueueing the generic LH BIA job.
  def associate_attachments!
    refs = attachment_keys.flat_map { |key| Array(open_struct_form.public_send(key)) }
    return if refs.empty?

    PersistentAttachment.where(guid: refs.map(&:confirmationCode)).find_each do |attachment|
      attachment.update(saved_claim_id: id)
    end
  end

  def generate_benefits_intake_metadata
    ::BenefitsIntake::Metadata.generate(
      parsed_form.dig('applicantName', 'first'),
      parsed_form.dig('applicantName', 'last'),
      parsed_form['vaFileNumber'].presence || parsed_form['ssn'],
      parsed_form.dig('mailingAddress', 'postalCode'),
      self.class.to_s,
      '22-10272', # doc type
      'EDU' # business line
    )
  end

  def send_email(email_type)
    EducationBenefitsClaims::NotificationEmail.new(id).deliver(email_type)
  end

  def personalisation
    {
      first_name: parsed_form.dig('applicantName', 'first'),
      last_name: parsed_form.dig('applicantName', 'last')
    }
  end

  def email
    parsed_form['emailAddress']
  end

  def retention_period
    60.days
  end
end
