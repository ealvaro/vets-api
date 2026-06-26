# frozen_string_literal: true

module SurvivorsBenefits::StructuredData::V2025::Section10
  ##
  # Section X
  # Build the medical, last, and/or burial expenses structured data entries.
  def build_section10
    fields.merge!(y_n_pair(any_reimbursement?, 'UNREIMBURSED_MED_EXPENSES_Y', 'UNREIMBURSED_MED_EXPENSES_N'))
    merge_care_expense_fields(form['careExpenses'] || [])
    merge_medical_expense_fields(form['medicalExpenses'] || [])
  end

  ##
  # Check if there are any reimbursements for care or medical expenses
  #
  # @return [Boolean] True if there are any reimbursements, false otherwise
  def any_reimbursement?
    form['careExpenses'].present? || form['medicalExpenses'].present?
  end

  ##
  # Build and merge the structured data fields for the care expenses
  #
  # @param care_expenses [Array<Hash>] An array of care expense hashes from the form
  def merge_care_expense_fields(care_expenses)
    care_expenses&.each_with_index do |expense, index|
      expense_num = index + 1
      merge_care_type_fields(expense_num, expense['careType'])
      # V2025: payment amount is a single field; no thousands/hundreds/cents breakdown.
      fields["AMNT_YOU_PAY#{expense_num}"] = format_currency(expense['paymentAmount'])
      fields.merge!(
        {
          "CB_EXPENSES_PAID_SP#{expense_num}" => expense['recipient'] == 'SURVIVING_SPOUSE',
          "CB_EXPENSES_PAID_OTHER#{expense_num}" => expense['recipient'] == 'OTHER',
          "NAME_OF_DEPENDENT#{expense_num}" => expense['recipientName'],
          "NAME_OF_PROVIDER#{expense_num}" => expense['provider'],
          "PMNT_RATE_INHOMECARE#{expense_num}" => format_currency(expense['ratePerHour']),
          "HRS_PER_WEEK#{expense_num}" => expense['hoursPerWeek'],
          "PROVIDER_START_DATE#{expense_num}" => format_date(expense.dig('careDateRange', 'from')),
          "PROVIDER_END_DATE#{expense_num}" => format_date(expense.dig('careDateRange', 'to')),
          "CB_NO_END_DATE#{expense_num}" => expense['noCareEndDate'] || false,
          "CB_PAYMENT_MONTHLY#{expense_num}" => expense['paymentFrequency'] == 'MONTHLY',
          "CB_PAYMENT_ANNUALLY#{expense_num}" => expense['paymentFrequency'] == 'ANNUALLY'
        }
      )
    end
  end

  ##
  # Build and merge the structured data fields for the care expense types
  #
  # @param expense_num [Integer] The number of the care expense (e.g., 1 for the first expense, 2 for the second, etc.)
  # @param care_type [String] The type of care (e.g., "CARE_FACILITY", "IN_HOME_CARE_ATTENDANT",
  #   "NURSING_HOME", "RESIDENTIAL_CARE")
  # V2025 adds NURSING_HOME and RESIDENTIAL_CARE care types alongside the existing two.
  def merge_care_type_fields(expense_num, care_type)
    fields.merge!(
      {
        "CB_PROVIDER_TYPE_NURSINGHOME#{expense_num}" => care_type == 'NURSING_HOME',
        "CB_PROVIDER_TYPE_DAYCARE#{expense_num}" => care_type == 'RESIDENTIAL_CARE',
        "CB_PROVIDER_TYPE_CAREFACILITY#{expense_num}" => care_type == 'CARE_FACILITY',
        "CB_PROVIDER_TYPE_INHOMECARE#{expense_num}" => care_type == 'IN_HOME_CARE_ATTENDANT'
      }
    )
  end

  ##
  # Build and merge the structured data fields for the medical expenses
  #
  # @param medical_expenses [Array<Hash>] An array of medical expense hashes from the form
  def merge_medical_expense_fields(medical_expenses)
    medical_expenses&.each_with_index do |expense, index|
      expense_num = index + 1
      recipient = expense['recipients'] || expense['recipient']
      # V2025: payment amount is a single field; no thousands/hundreds/cents breakdown.
      fields["MEDAMNT_YOU_PAY#{expense_num}"] = format_currency(expense['paymentAmount'])
      fields.merge!(
        {
          "MED_EXPENSES_SP#{expense_num}" => recipient == 'SURVIVING_SPOUSE',
          "MED_EXPENSES_VET#{expense_num}" => recipient == 'VETERAN',
          "MED_EXPENSES_CHILD#{expense_num}" => recipient == 'CHILD',
          "MED_EXPENSES_CHILDNAME#{expense_num}" => expense['childName'],
          "PAID_TO_PROVIDER#{expense_num}" => expense['provider'],
          "PAID_TO_PURPOSE#{expense_num}" => expense['purpose'],
          "DATE_COSTS_INCURRED_START#{expense_num}" => format_date(expense['paymentDate']),
          "CB_PMNT_FREQUENCY_MONTHLY#{expense_num}" => expense['paymentFrequency'] == 'MONTHLY',
          "CB_PMNT_FREQUENCY_ANNUALLY#{expense_num}" => expense['paymentFrequency'] == 'ANNUALLY',
          "CB_PMNT_FREQUENCY_ONETIME#{expense_num}" => expense['paymentFrequency'] == 'ONE_TIME'
        }
      )
    end
  end
end
