# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    # Section IX: Income And Assets (current income entries)
    class Section9 < Section
      include ::PdfFill::Forms::FormHelper
      include Helpers

      INCOME_RECIPIENT_FIELDS = [
        'form1[0].#subform[215].RadioButtonList[38]',
        'form1[0].#subform[215].RadioButtonList[40]',
        'form1[0].#subform[215].RadioButtonList[42]',
        'form1[0].#subform[215].RadioButtonList[44]'
      ].freeze

      INCOME_TYPE_FIELDS = [
        'form1[0].#subform[215].RadioButtonList[39]',
        'form1[0].#subform[215].RadioButtonList[41]',
        'form1[0].#subform[215].RadioButtonList[43]',
        'form1[0].#subform[215].RadioButtonList[45]'
      ].freeze

      INCOME_CHILD_NAME_FIELDS = [
        'form1[0].#subform[215].Name_Of_Child[0]',
        'form1[0].#subform[215].Name_Of_Child[1]',
        'form1[0].#subform[215].Name_Of_Child[2]',
        'form1[0].#subform[215].Name_Of_Child[3]'
      ].freeze

      INCOME_OTHER_TYPE_FIELDS = [
        'form1[0].#subform[215].Specify_Type_Of_Income[3]',
        'form1[0].#subform[215].Specify_Type_Of_Income[0]',
        'form1[0].#subform[215].Specify_Type_Of_Income[1]',
        'form1[0].#subform[215].Specify_Type_Of_Income[2]'
      ].freeze

      INCOME_PAYER_FIELDS = [
        'form1[0].#subform[215].Income_Payer[0]',
        'form1[0].#subform[215].Income_Payer[1]',
        'form1[0].#subform[215].Income_Payer[2]',
        'form1[0].#subform[215].Income_Payer[3]'
      ].freeze

      INCOME_AMOUNT_THOUSANDS_FIELDS = [
        'form1[0].#subform[215].Monthly_Amount[0]',
        'form1[0].#subform[215].Monthly_Amount[3]',
        'form1[0].#subform[215].Monthly_Amount[6]',
        'form1[0].#subform[215].Monthly_Amount[9]'
      ].freeze

      INCOME_AMOUNT_DOLLARS_FIELDS = [
        'form1[0].#subform[215].Monthly_Amount[1]',
        'form1[0].#subform[215].Monthly_Amount[4]',
        'form1[0].#subform[215].Monthly_Amount[7]',
        'form1[0].#subform[215].Monthly_Amount[10]'
      ].freeze

      INCOME_AMOUNT_CENTS_FIELDS = [
        'form1[0].#subform[215].Monthly_Amount[2]',
        'form1[0].#subform[215].Monthly_Amount[5]',
        'form1[0].#subform[215].Monthly_Amount[8]',
        'form1[0].#subform[215].Monthly_Amount[11]'
      ].freeze

      INCOME_ENTRY_COUNT = INCOME_RECIPIENT_FIELDS.length

      # Form data key per income block, so each block's fields overflow independently. Routing the
      # four blocks through a single KEY array instead would hand them to
      # PdfFill::HashConverter#transform_array, where one long value overflows the whole array:
      # the default branch stamps the placeholder into `first_key`, a RadioButtonList widget, and
      # `label_all` drops the nested monthlyIncome amounts.
      INCOME_ENTRY_KEYS = %w[incomeEntryOne incomeEntryTwo incomeEntryThree incomeEntryFour].freeze

      # Question suffix per income block: 9I, 9J, 9K, 9L.
      INCOME_ENTRY_SUFFIXES = %w[I J K L].freeze

      # Characters each Section IX income widget shows in full, measured from the V2022 template
      # (CourierNewPSMT 10pt, 0.6 em advance, no /MaxLen, DoNotScroll set).
      RECIPIENT_NAME_LIMIT = 28
      INCOME_TYPE_OTHER_LIMIT = 28
      INCOME_PAYER_LIMIT = 24

      class << self
        # Overflow metadata for a KEY entry: +limit+ is what HashConverter#overflow? trips on, and
        # the question fields are what ExtrasGeneratorV2 needs to place and label the value.
        def overflow_hash(max, number, suffix, label, text)
          {
            limit: max,
            question_num: number,
            question_suffix: suffix,
            question_label: label,
            question_text: text
          }
        end

        # KEY fragment for one income block. The three free-text fields carry overflow metadata so a
        # value too wide for its widget is replaced on the form by the placeholder and printed in
        # full on the overflow page; without it the widget silently clips the text.
        def income_entry_key(index)
          ordinal = index + 1
          suffix = INCOME_ENTRY_SUFFIXES[index]

          {
            'recipient' => { key: INCOME_RECIPIENT_FIELDS[index] },
            'recipientName' =>
              overflow_hash(RECIPIENT_NAME_LIMIT, 9, suffix, "Recipient name #{ordinal}",
                            "RECIPIENT NAME #{ordinal}").merge(key: INCOME_CHILD_NAME_FIELDS[index]),
            'incomeType' => { key: INCOME_TYPE_FIELDS[index] },
            'incomeTypeOther' =>
              overflow_hash(INCOME_TYPE_OTHER_LIMIT, 9, suffix, "Type of income #{ordinal}",
                            "TYPE OF INCOME #{ordinal}").merge(key: INCOME_OTHER_TYPE_FIELDS[index]),
            'incomePayer' =>
              overflow_hash(INCOME_PAYER_LIMIT, 9, suffix, "Income payer #{ordinal}",
                            "INCOME PAYER #{ordinal}").merge(key: INCOME_PAYER_FIELDS[index]),
            'monthlyIncome' => {
              'thousands' => { key: INCOME_AMOUNT_THOUSANDS_FIELDS[index] },
              'dollars' => { key: INCOME_AMOUNT_DOLLARS_FIELDS[index] },
              'cents' => { key: INCOME_AMOUNT_CENTS_FIELDS[index] }
            }
          }
        end
      end

      RECIPIENT_VALUES = {
        'SURVIVING_SPOUSE' => '0',
        'CHILD' => '1'
      }.freeze

      INCOME_TYPE_VALUES = {
        'SOCIAL_SECURITY' => 1,
        'INTEREST_DIVIDENDS' => 2,
        'CIVIL_SERVICE' => 5,
        'PENSION_RETIREMENT' => 4,
        'OTHER' => 3
      }.freeze

      # --- Asset questions ---
      KEY = {
        'p15HeaderVeteranSocialSecurityNumber' => {
          'first' => {
            key: 'form1[0].#subform[215].VeteransSocialSecurityNumber_FirstThreeNumbers[5]'
          },
          'second' => {
            key: 'form1[0].#subform[215].VeteransSocialSecurityNumber_SecondTwoNumbers[5]'
          },
          'third' => {
            key: 'form1[0].#subform[215].VeteransSocialSecurityNumber_LastFourNumbers[5]'
          }
        },
        'totalNetWorth' => { key: 'form1[0].#subform[211].RadioButtonList[24]' },
        'netWorthEstimation' => {
          'thousands' => { key: 'form1[0].#subform[211].Amount[0]' },
          'dollars' => { key: 'form1[0].#subform[211].Amount[1]' },
          'cents' => { key: 'form1[0].#subform[211].Amount[2]' }
        },
        'transferredAssets' => { key: 'form1[0].#subform[211].RadioButtonList[25]' },
        'homeOwnership' => { key: 'form1[0].#subform[211].RadioButtonList[26]' },
        'homeAcreageMoreThanTwo' => { key: 'form1[0].#subform[211].RadioButtonList[27]' },
        'homeAcreageValue' => {
          'millions' => { key: 'form1[0].#subform[211].Total_Annual_Earnings_Amount[5]' },
          'thousands' => { key: 'form1[0].#subform[211].Total_Annual_Earnings_Amount[6]' },
          'dollars' => { key: 'form1[0].#subform[211].Total_Annual_Earnings_Amount[4]' }
        },
        'landMarketable' => { key: 'form1[0].#subform[211].RadioButtonList[28]' },
        'moreThanFourIncomeSources' => { key: 'form1[0].#subform[211].RadioButtonList[29]' },
        'otherIncome' => { key: 'form1[0].#subform[211].RadioButtonList[32]' }
      }.merge(
        INCOME_ENTRY_KEYS.each_with_index.to_h { |name, index| [name, income_entry_key(index)] }
      ).freeze

      def expand(form_data = {})
        form_data['p15HeaderVeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])

        # --- Expand asset answers ---
        form_data['totalNetWorth'] = yes_no_radio(form_data['totalNetWorth'])
        form_data['netWorthEstimation'] = normalize_small_currency(form_data['netWorthEstimation'])
        form_data['transferredAssets'] = yes_no_radio(form_data['transferredAssets'])
        form_data['homeOwnership'] = yes_no_radio(form_data['homeOwnership'])
        form_data['homeAcreageMoreThanTwo'] = yes_no_radio(form_data['homeAcreageMoreThanTwo'])
        form_data['homeAcreageValue'] = normalize_large_currency(form_data['homeAcreageValue'])
        form_data['landMarketable'] = yes_no_radio(form_data['landMarketable'])

        # --- Expand income entries ---
        entries = Array(form_data['incomeEntries'])

        INCOME_ENTRY_KEYS.each_with_index do |entry_key, index|
          entry = entries[index]
          form_data[entry_key] = entry.present? ? transform_income_entry(entry) : empty_income_entry
        end

        more_than_four = form_data['moreThanFourIncomeSources']
        more_than_four = entries.length > INCOME_ENTRY_COUNT if more_than_four.nil?
        form_data['moreThanFourIncomeSources'] = more_than_four ? 1 : 2 # weird values on form

        # --- Other income ---
        form_data['otherIncome'] = yes_no_radio(form_data['otherIncome']) # flag for 21P-0969

        form_data
      end

      private

      def transform_income_entry(entry)
        data = {}

        recipient = entry['recipient']
        data['recipient'] = RECIPIENT_VALUES[recipient] || 'Off'
        data['recipientName'] = entry['recipientName']

        income_type = entry['incomeType']
        data['incomeType'] = INCOME_TYPE_VALUES[income_type] || 'Off'
        data['incomeTypeOther'] = entry['incomeTypeOther'] || entry['otherTypeExplanation'] || ''
        data['incomePayer'] = entry['incomePayer'] || entry['payer']

        amount_value = entry['monthlyIncome'] || entry['amount']
        amount_parts = coerce_small_currency_hash(amount_value)
        data['monthlyIncome'] = normalize_small_amount_fields(amount_parts)

        data
      end

      # --- Helpers shared across asset & income sections ---
      def normalize_small_currency(value)
        amount_hash = coerce_small_currency_hash(value)
        normalize_small_amount_fields(amount_hash)
      end

      def normalize_small_amount_fields(amount_hash)
        normalized = {}
        %w[thousands dollars].each do |part|
          value = amount_hash[part]
          normalized[part] = value&.to_s&.strip&.rjust(3, ' ')
        end
        normalized['cents'] = amount_hash['cents']&.to_s&.strip&.rjust(2, '0')

        normalized
      end

      def normalize_large_currency(value)
        amount_hash = coerce_large_currency_hash(value)
        {
          'millions' => format_amount_part(amount_hash['millions'], 1),
          'thousands' => format_amount_part(amount_hash['thousands'], 3),
          'dollars' => format_amount_part(amount_hash['dollars'], 3)
        }
      end

      def coerce_small_currency_hash(value)
        return value if value.is_a?(Hash)
        return {} if value.blank?

        split_currency_amount_sm(value, { 'thousands' => 3 })
      end

      def coerce_large_currency_hash(value)
        return value if value.is_a?(Hash)
        return {} if value.blank?

        split_currency_amount_lg(value, { 'millions' => 1, 'thousands' => 3, 'dollars' => 3, 'cents' => 2 })
      end

      def format_amount_part(value, length)
        value&.to_s&.strip&.rjust(length, ' ')
      end

      def yes_no_radio(value)
        case value
        when true then 1
        when false then 2
        else 'Off'
        end
      end

      def empty_income_entry
        {
          'recipient' => 'Off',
          'childName' => nil,
          'incomeType' => 'Off',
          'incomeTypeOther' => nil,
          'incomePayer' => nil
        }
      end
    end
  end
end
