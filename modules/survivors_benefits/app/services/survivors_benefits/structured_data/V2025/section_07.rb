# frozen_string_literal: true

module SurvivorsBenefits::StructuredData::V2025::Section07
  ##
  # Section VII
  # Build the D.I.C. structured data entries.
  #
  def build_section7
    merge_dic_type_fields(form['benefit'])
    treatments = form['treatments'] || []
    treatments&.each_with_index do |treatment, index|
      center_num = index + 1
      # V2025 splits facility into name and location; V2022 used a single combined field.
      fields.merge!(
        {
          "NAME_MED_CENTER_#{center_num}" => treatment.dig('facilityInfo', 'vaMedicalCenterName'),
          "LOC_MED_CENTER_#{center_num}" => treatment_location(treatment),
          "DATE_OF_TREATMENT_START#{center_num}" => format_date(treatment['startDate']),
          "DATE_OF_TREATMENT_END#{center_num}" => format_date(treatment['endDate'])
        }
      )
    end
  end

  ##
  # Build the structured data fields for the D.I.C. benefit type.
  #
  # @param benefit [String] The type of D.I.C. benefit (e.g., "DIC", "1151DIC", "pactActDIC")
  def merge_dic_type_fields(benefit)
    fields.merge!(
      {
        'BENEFIT_DIC' => benefit == 'DIC',
        'BENEFIT_DIC38' => benefit == '1151DIC',
        'CLAIM_TYPE_DIC_PACTACT' => benefit == 'pactActDIC'
      }
    )
  end

  def treatment_location(treatment)
    city = treatment.dig('facilityInfo', 'city').presence
    state = treatment.dig('facilityInfo', 'state').presence
    [city, state].compact.join(', ').presence
  end
end
