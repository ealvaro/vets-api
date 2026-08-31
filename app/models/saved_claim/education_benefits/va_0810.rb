# frozen_string_literal: true

class SavedClaim::EducationBenefits::VA0810 < SavedClaim::EducationBenefits
  add_form_and_validation('22-0810')

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
      '22-0810', # doc type
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

  # Overridden so callers can pass fill_options through to PdfFill::Filler's generic
  # ExtrasGeneratorV2 path (see make_hash_converter in lib/pdf_fill/filler.rb).
  # This form is submitted through the Lighthouse benefits_intake API. The submission job
  # already appends its own footer for education forms, so we default to omitting
  # ExtrasGeneratorV2's built-in footer here to avoid duplicating it (worth revisiting in a
  # follow-up PR to move that footer logic into the extras generator instead). We also omit
  # the esign stamp since no IAL2 authentication claim is applicable here. Also opts into the
  # "additional page" wording (vs. the default "attachment" wording) for overflow placeholder
  # text and header.
  def to_pdf(file_name = nil, fill_options = {})
    fill_options = {
      extras_redesign: true,
      omit_esign_stamp: true,
      omit_footer: true,
      placeholder_text: 'See additional page',
      header_label: 'ADDITIONAL PAGE'
    }.merge(fill_options)
    PdfFill::Filler.fill_form(self, file_name, fill_options)
  end
end
