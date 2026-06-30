# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      # Section IX: Income And Assets (current income entries)
      class Section9 < Section
        include ::PdfFill::Forms::FormHelper
        include Helpers
        KEY = {
          'p15HeaderVeteranSocialSecurityNumber' => {
            'first' => {
              key: 'form1[0].#subform[160].VeteransSocialSecurityNumber_FirstThreeNumbers[5]'
            },
            'second' => {
              key: 'form1[0].#subform[160].VeteransSocialSecurityNumber_SecondTwoNumbers[5]'
            },
            'third' => {
              key: 'form1[0].#subform[160].VeteransSocialSecurityNumber_LastFourNumbers[5]'
            }
          },
          'totalNetWorthYes' => { key: 'form1[0].#subform[156].Checkboxyes[0]' },
          'totalNetWorthNo' => { key: 'form1[0].#subform[156].CheckboxNO[1]' },
          'netWorthEstimation' => { key: 'form1[0].#subform[156].Routing_Or_Transit_Number[3]' },
          'transferredAssetsYes' => { key: 'form1[0].#subform[156].Checkboxyes[1]' },
          'transferredAssetsNo' => { key: 'form1[0].#subform[156].Checkboxno[0]' },
          'homeOwnershipYes' => { key: 'form1[0].#subform[156].Checkboxyes[2]' },
          'homeOwnershipNo' => { key: 'form1[0].#subform[156].Checkboxno[1]' },
          'homeAcreageMoreThanTwoYes' => { key: 'form1[0].#subform[156].Checkboxyes[3]' },
          'homeAcreageMoreThanTwoNo' => { key: 'form1[0].#subform[156].Checkboxno[2]' },
          'homeAcreageValue' => { key: 'form1[0].#subform[156].Routing_Or_Transit_Number[4]' },
          'landMarketableYes' => { key: 'form1[0].#subform[156].Checkboxyes[4]' },
          'landMarketableNo' => { key: 'form1[0].#subform[156].Checkboxno[3]' },
          'noIncome' => { key: 'form1[0].#subform[156].JF06[3]' },
          'oneToFour' => { key: 'form1[0].#subform[156].JF14[3]' },
          'fivePlus' => { key: 'form1[0].#subform[156].JF08[3]' },
          'otherIncomeYes' => { key: 'form1[0].#subform[156].Checkboxyes[5]' },
          'otherIncomeNo' => { key: 'form1[0].#subform[156].Checkboxno[4]' },
          'incomeEntryOne' => {
            'survivingSpouse' => { key: 'form1[0].#subform[160].Surviving_Spouse[0]' },
            'custodian' => { key: 'form1[0].#subform[160].Surviving_Spouse[1]' },
            'child' => { key: 'form1[0].#subform[160].Child_Specify[0]' },
            'custodianSpouse' => { key: 'form1[0].#subform[160].Child_Specify[1]' },
            'recipientName' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'I',
              question_label: 'Recipient name 1',
              question_text: 'RECIPIENT NAME 1',
              key: 'form1[0].#subform[160].Name_Of_Child[0]'
            },
            'socialSecurity' => { key: 'form1[0].#subform[160].Social_Security[0]' },
            'interestDividends' => { key: 'form1[0].#subform[160].Interest_Dividends[0]' },
            'civilService' => { key: 'form1[0].#subform[160].Civil_Service[0]' },
            'pensionRetirement' => { key: 'form1[0].#subform[160].Pension_Retirement[0]' },
            'other' => { key: 'form1[0].#subform[160].Other_Specify_Type_Of_Income[0]' },
            'incomeTypeOther' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'I',
              question_label: 'Type of income 1',
              question_text: 'TYPE OF INCOME 1',
              key: 'form1[0].#subform[160].Specify_Type_Of_Income[3]'
            },
            'incomePayer' => {
              limit: 24,
              question_num: 9,
              question_suffix: 'I',
              question_label: 'Income payer 1',
              question_text: 'INCOME PAYER 1',
              key: 'form1[0].#subform[160].Income_Payer[0]'
            },
            'monthlyIncome' => { key: 'form1[0].#subform[160].VETERANS_SERVICE_NUMBER[1]' }
          },
          'incomeEntryTwo' => {
            'survivingSpouse' => { key: 'form1[0].#subform[160].Surviving_Spouse[2]' },
            'custodian' => { key: 'form1[0].#subform[160].Surviving_Spouse[3]' },
            'child' => { key: 'form1[0].#subform[160].Child_Specify[2]' },
            'custodianSpouse' => { key: 'form1[0].#subform[160].Child_Specify[3]' },
            'recipientName' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'J',
              question_label: 'Recipient name 2',
              question_text: 'RECIPIENT NAME 2',
              key: 'form1[0].#subform[160].Name_Of_Child[1]'
            },
            'socialSecurity' => { key: 'form1[0].#subform[160].Social_Security[1]' },
            'interestDividends' => { key: 'form1[0].#subform[160].Interest_Dividends[1]' },
            'civilService' => { key: 'form1[0].#subform[160].Civil_Service[1]' },
            'pensionRetirement' => { key: 'form1[0].#subform[160].Pension_Retirement[1]' },
            'other' => { key: 'form1[0].#subform[160].Other_Specify_Type_Of_Income[1]' },
            'incomeTypeOther' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'J',
              question_label: 'Type of income 2',
              question_text: 'TYPE OF INCOME 2',
              key: 'form1[0].#subform[160].Specify_Type_Of_Income[0]'
            },
            'incomePayer' => {
              limit: 24,
              question_num: 9,
              question_suffix: 'J',
              question_label: 'Income payer 2',
              question_text: 'INCOME PAYER 2',
              key: 'form1[0].#subform[160].Income_Payer[1]'
            },
            'monthlyIncome' => { key: 'form1[0].#subform[160].VETERANS_SERVICE_NUMBER[2]' }
          },
          'incomeEntryThree' => {
            'survivingSpouse' => { key: 'form1[0].#subform[160].Surviving_Spouse[4]' },
            'custodian' => { key: 'form1[0].#subform[160].Surviving_Spouse[5]' },
            'child' => { key: 'form1[0].#subform[160].Child_Specify[4]' },
            'custodianSpouse' => { key: 'form1[0].#subform[160].Child_Specify[5]' },
            'recipientName' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'K',
              question_label: 'Recipient name 3',
              question_text: 'RECIPIENT NAME 3',
              key: 'form1[0].#subform[160].Name_Of_Child[2]'
            },
            'socialSecurity' => { key: 'form1[0].#subform[160].Social_Security[2]' },
            'interestDividends' => { key: 'form1[0].#subform[160].Interest_Dividend[0]' },
            'civilService' => { key: 'form1[0].#subform[160].Civil_Service[2]' },
            'pensionRetirement' => { key: 'form1[0].#subform[160].Pension_Retirement[2]' },
            'other' => { key: 'form1[0].#subform[160].Other_Type_Of_Income[0]' },
            'incomeTypeOther' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'K',
              question_label: 'Type of income 3',
              question_text: 'TYPE OF INCOME 3',
              key: 'form1[0].#subform[160].Specify_Type_Of_Income[1]'
            },
            'incomePayer' => {
              limit: 24,
              question_num: 9,
              question_suffix: 'K',
              question_label: 'Income payer 3',
              question_text: 'INCOME PAYER 3',
              key: 'form1[0].#subform[160].Income_Payer[2]'
            },
            'monthlyIncome' => { key: 'form1[0].#subform[160].VETERANS_SERVICE_NUMBER[3]' }
          },
          'incomeEntryFour' => {
            'survivingSpouse' => { key: 'form1[0].#subform[160].Surviving_Spouse[6]' },
            'custodian' => { key: 'form1[0].#subform[160].Surviving_Spouse[7]' },
            'child' => { key: 'form1[0].#subform[160].Child_Specify[6]' },
            'custodianSpouse' => { key: 'form1[0].#subform[160].Child_Specify[7]' },
            'recipientName' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'L',
              question_label: 'Recipient name 4',
              question_text: 'RECIPIENT NAME 4',
              key: 'form1[0].#subform[160].Name_Of_Child[3]'
            },
            'socialSecurity' => { key: 'form1[0].#subform[160].Social_Security[3]' },
            'interestDividends' => { key: 'form1[0].#subform[160].Interest_Dividends[2]' },
            'civilService' => { key: 'form1[0].#subform[160].Civil_Service[3]' },
            'pensionRetirement' => { key: 'form1[0].#subform[160].Pension_Retirement[3]' },
            'other' => { key: 'form1[0].#subform[160].Other_Specify_Type_Of_Income[2]' },
            'incomeTypeOther' => {
              limit: 28,
              question_num: 9,
              question_suffix: 'L',
              question_label: 'Specify type of income 4 (if other)',
              question_text: 'SPECIFY TYPE OF INCOME 4 (IF OTHER)',
              key: 'form1[0].#subform[160].Specify_Type_Of_Income[2]'
            },
            'incomePayer' => {
              limit: 24,
              question_num: 9,
              question_suffix: 'L',
              question_label: 'Income payer 4',
              question_text: 'INCOME PAYER 4',
              key: 'form1[0].#subform[160].Income_Payer[3]'
            },
            'monthlyIncome' => { key: 'form1[0].#subform[160].VETERANS_SERVICE_NUMBER[4]' }
          }
        }.freeze
        def expand(form_data = {})
          form_data['p15HeaderVeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])

          map_yes_no_checkboxes(form_data, 'totalNetWorth', 'totalNetWorthYes', 'totalNetWorthNo')
          map_yes_no_checkboxes(form_data, 'transferredAssets', 'transferredAssetsYes', 'transferredAssetsNo')
          map_yes_no_checkboxes(form_data, 'homeOwnership', 'homeOwnershipYes', 'homeOwnershipNo')
          map_yes_no_checkboxes(
            form_data,
            'homeAcreageMoreThanTwo',
            'homeAcreageMoreThanTwoYes',
            'homeAcreageMoreThanTwoNo'
          )
          map_yes_no_checkboxes(form_data, 'landMarketable', 'landMarketableYes', 'landMarketableNo')

          expand_income_entries(form_data)

          form_data['noIncome'] = form_data['incomeSourcesCount'] == 'NO_INCOME' ? '1' : 'Off'
          form_data['oneToFour'] = form_data['incomeSourcesCount'] == 'ONE_TO_FOUR_SOURCES' ? '1' : 'Off'
          form_data['fivePlus'] = form_data['incomeSourcesCount'] == 'MORE_THAN_FIVE_SOURCES' ? '1' : 'Off'

          map_yes_no_checkboxes(form_data, 'otherIncome', 'otherIncomeYes', 'otherIncomeNo')

          form_data
        end

        private

        def map_yes_no_checkboxes(form_data, source_key, yes_key, no_key)
          case form_data[source_key]
          when true
            form_data[yes_key] = '1'
            form_data[no_key] = 'Off'
          when false
            form_data[yes_key] = 'Off'
            form_data[no_key] = '1'
          else
            form_data[yes_key] = 'Off'
            form_data[no_key] = 'Off'
          end
        end

        def expand_entry(entry = {})
          recipient = entry['recipient']
          income_type = entry['incomeType']
          entry.merge({
                        'survivingSpouse' => recipient == 'SURVIVING_SPOUSE' ? '1' : 'Off',
                        'custodian' => recipient == 'CUSTODIAN' ? '1' : 'Off',
                        'child' => recipient == 'CHILD' ? '1' : 'Off',
                        'custodianSpouse' => recipient == 'CUSTODIAN_SPOUSE' ? '1' : 'Off',
                        'recipientName' => entry['recipientName'],
                        'socialSecurity' => income_type == 'SOCIAL_SECURITY' ? '1' : 'Off',
                        'interestDividends' => income_type == 'INTEREST_DIVIDENDS' ? '1' : 'Off',
                        'civilService' => income_type == 'CIVIL_SERVICE' ? '1' : 'Off',
                        'pensionRetirement' => income_type == 'PENSION_RETIREMENT' ? '1' : 'Off',
                        'other' => income_type == 'OTHER' ? '1' : 'Off',
                        'incomeTypeOther' => entry['incomeTypeOther'],
                        'incomePayer' => entry['incomePayer'],
                        'monthlyIncome' => entry['monthlyIncome']
                      })
        end

        def expand_income_entries(form_data)
          entries = Array(form_data['incomeEntries']).map { |entry| expand_entry(entry) }
          form_data['incomeEntryOne'] = entries.first || {}
          form_data['incomeEntryTwo'] = entries.second || {}
          form_data['incomeEntryThree'] = entries.third || {}
          form_data['incomeEntryFour'] = entries.fourth || {}
        end
      end
    end
  end
end
