# frozen_string_literal: true

module SurvivorsBenefits::StructuredData::V2022::Section12
  ##
  # Section XII
  # Build and merge claim certification structured data entries.
  def build_section12
    claimant_name = build_name(form['claimantFullName'])
    fields.merge!(
      {
        'CB_FURTHER_EVD_CLAIM_SUPPORT' => false,
        'CLAIM_TYPE_FULLY_DEVELOPED_CHK' => '',
        'CLAIMANT_SIGNATURE' => claimant_name[:full],
        'DATE_OF_CLAIMANT_SIGNATURE' => format_date(form['dateSigned'] || Date.current)
      }
    )
  end
end
