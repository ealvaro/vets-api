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
end
