# frozen_string_literal: true

module SurvivorsBenefits::StructuredData::V2025::Section09
  ##
  # Section IX
  # Build Income and Asset structured data entries.
  #
  # @param form [Hash]
  # @return [Hash]
  def build_section9
    merge_income_fields(form['incomeEntries'])
    merge_income_source_fields(form['moreThanFourIncomeSources'])
    fields.merge!(y_n_pair(form['landMarketable'], 'MARKETABLE_LAND_2ACR_Y', 'MARKETABLE_LAND_2ACR_N'))
    fields.merge!(y_n_pair(form['transferredAssets'], 'TRANSFER_ASSETS_LAST3Y_Y', 'TRANSFER_ASSETS_LAST3Y_N'))
    fields.merge!(y_n_pair(form['homeOwnership'], 'OWN_PRIMARY_RESIDENCE_Y', 'OWN_PRIMARY_RESIDENCE_N'))
    fields.merge!(y_n_pair(form['homeAcreageMoreThanTwo'], 'RESLOT_OVER_2ACR_Y', 'RESLOT_OVER_2ACR_N'))
    fields.merge!(y_n_pair(form['otherIncome'], 'PREV_YEAR_OTHER_INCOME_YES', 'PREV_YEAR_OTHER_INCOME_NO'))
    # V2025: threshold raised to $75K and uses different field names.
    fields.merge!(y_n_pair(form['totalNetWorth'], 'ASSETS_OVER_75K_Y', 'ASSETS_OVER_75K_N'))
    fields.merge!(
      {
        'AMNT_ESTIMATE_ASSETS' => format_currency(form['netWorthEstimation'] || 0),
        'AMNT_VALUE_OF_LOT' => format_currency(form['homeAcreageValue'] || 0)
      }
    )
  end

  # V2025: income source is an enum string instead of a boolean moreThanFour flag.
  def merge_income_source_fields(income_source)
    fields.merge!(
      {
        'NO_INCOME' => income_source == 'NO_INCOME',
        '1_4_INCSOURCE_Y' => income_source == 'ONE_TO_FOUR_SOURCES',
        'MORETHAN4_INCSOURCE_Y' => income_source == 'MORE_THAN_FIVE_SOURCES'
      }
    )
  end

  ##
  # Build and merge the structured data fields for the claimant's income entries.
  #
  # @param incomes [Array<Hash>] An array of income entry hashes from the form
  def merge_income_fields(incomes)
    incomes&.each_with_index do |income, index|
      income_num = index + 1
      # V2025: monthly income is a single amount field; no thousands/hundreds/cents breakdown.
      fields["MONTHLY_GROSS_#{income_num}"] = format_currency(income['monthlyIncome'])
      fields.merge!(merge_income_recipient_fields(income, income_num))
      fields.merge!(merge_income_type_fields(income, income_num))
    end
  end

  def merge_income_recipient_fields(income, income_num)
    recipient = income['recipient']
    {
      "CB_INC_RECIPIENT#{income_num}_SP" => recipient == 'SURVIVING_SPOUSE',
      "CB_INC_RECIPIENT#{income_num}_CHILD" => recipient == 'CHILD',
      "CB_INC_RECIPIENT#{income_num}_CSTDN" => recipient == 'CUSTODIAN',
      "CB_INC_RECIPIENT#{income_num}_CSTDN_SP" => recipient == 'CUSTODIAN_SPOUSE',
      "NAME_OF_CHILD_INCOMETYPE#{income_num}" => income['recipientName']
    }
  end

  def merge_income_type_fields(income, income_num)
    income_type = income['incomeType']
    {
      "CB_INCOMETYPE#{income_num}_SS" => income_type == 'SOCIAL_SECURITY',
      "CB_INCOMETYPE#{income_num}_PENSION" => income_type == 'PENSION_RETIREMENT',
      "CB_INCOMETYPE#{income_num}_CIVIL" => income_type == 'CIVIL_SERVICE',
      "CB_INCOMETYPE#{income_num}_INTEREST" => income_type == 'INTEREST_DIVIDENDS',
      "CB_INCOMETYPE#{income_num}_OTHER" => income_type == 'OTHER',
      "CB_INCOMETYPE#{income_num}_OTHERSPECIFY" => income['incomeTypeOther'],
      "INCOME_PAYER_#{income_num}" => income['incomePayer']
    }
  end
end
