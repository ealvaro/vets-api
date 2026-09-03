# frozen_string_literal: true

class SavedClaim::EducationBenefits::VA10278 < SavedClaim::EducationBenefits
  add_form_and_validation('22-10278')

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
    return super(file_name) unless extras_redesign_enabled?

    fill_options = {
      extras_redesign: true,
      omit_esign_stamp: true,
      omit_footer: true,
      placeholder_text: 'See additional page',
      header_label: 'ADDITIONAL PAGE'
    }.merge(fill_options)
    PdfFill::Filler.fill_form(self, file_name, fill_options)
  end

  def after_submit(user)
    user_account_uuid = user&.user_account_uuid
    EducationForm::SubmitEducationBenefitsClaimJob.perform_async(id, user_account_uuid)
  end

  def generate_benefits_intake_metadata
    personal_info = parsed_form['claimantPersonalInformation']
    ::BenefitsIntake::Metadata.generate(
      personal_info['fullName']['first'],
      personal_info['fullName']['last'],
      personal_info['vaFileNumber'] || personal_info['ssn'],
      parsed_form['claimantAddress']['postalCode'],
      self.class.to_s,
      '22-10278', # doc type
      'EDU' # busines line
    )
  end

  def send_email(email_type)
    EducationBenefitsClaims::NotificationEmail.new(id).deliver(email_type)
  end

  # the personalization params to send with VANotify
  def personalisation
    full_name = parsed_form['claimantPersonalInformation']['fullName']
    {
      first_name: full_name['first'],
      last_name: full_name['last']
    }
  end

  # the email address to send VANotify success/failure emails to
  def email
    parsed_form['claimantContactInformation']['emailAddress']
  end

  def retention_period
    60.days
  end

  private

  def extras_redesign_enabled?
    Settings.vsp_environment == 'staging' || Rails.env.development? || Rails.env.test?
  end
end
