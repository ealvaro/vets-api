# frozen_string_literal: true

class SavedClaim::EducationBenefits::VA10216 < SavedClaim::EducationBenefits
  add_form_and_validation('22-10216')

  def retention_period
    60.days
  end

  # Overridden so callers can pass fill_options through to PdfFill::Filler's generic
  # ExtrasGeneratorV2 path (see make_hash_converter in lib/pdf_fill/filler.rb).
  # This form isn't submitted through the Lighthouse benefits_intake API, so we default to
  # omitting the esign stamp/footer (no IAL2 authentication claim is applicable here). Also
  # opts into the "additional page" wording (vs. the default "attachment" wording) for
  # overflow placeholder text and header.
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
