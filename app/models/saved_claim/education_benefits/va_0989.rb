# frozen_string_literal: true

class SavedClaim::EducationBenefits::VA0989 < SavedClaim::EducationBenefits
  add_form_and_validation('22-0989')

  def requires_authenticated_user?
    true
  end

  def retention_period
    60.days
  end

  def after_submit(_user)
    # 22-0989 is delivered via the nightly education spool file, not Benefits Intake.
    # PdfFill::Forms::Va220989 remains available for QA and possible future veteran PDF download.
  end

  # Uses the V2 extras generator (header/footer/page numbers on overflow pages). Also opts
  # into the "additional page" wording (vs. the default "attachment" wording) for overflow
  # placeholder text and header.
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
