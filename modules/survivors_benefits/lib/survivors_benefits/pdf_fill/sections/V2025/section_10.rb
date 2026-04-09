# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      # Section X: Information About Your Medical Or Other Expense
      class Section10 < Section
        KEY = {
          'p16HeaderVeteranSocialSecurityNumber' => {
            'first' => {
              key: 'form1[0].#subform[161].VeteransSocialSecurityNumber_FirstThreeNumbers[6]'
            },
            'second' => {
              key: 'form1[0].#subform[161].VeteransSocialSecurityNumber_SecondTwoNumbers[6]'
            },
            'third' => {
              key: 'form1[0].#subform[161].VeteransSocialSecurityNumber_LastFourNumbers[6]'
            }
          },
          'anythingToReportYes' => { key: 'form1[0].#subform[160].Checkboxyes[6]' },
          'anythingToReportNo' => { key: 'form1[0].#subform[160].Checkboxno[5]' },
          'careExpenseOne' => {
            'recipientSurvivingSpouse' => { key: 'form1[0].#subform[160].#field[291]' },
            'recipientOther' => { key: 'form1[0].#subform[160].#field[290]' },
            'recipientName' => { key: 'form1[0].#subform[160].OTHER_Specify[0]' },
            'provider' => { key: 'form1[0].#subform[160].Name_Of_Provider_And_Type_Of_Care[0]' },
            'careNursingHome' => { key: 'form1[0].#subform[160].#field[346]' },
            'careResidential' => { key: 'form1[0].#subform[160].#field[347]' },
            'careAdultDayCare' => { key: 'form1[0].#subform[160].#field[288]' },
            'careInHomeCare' => { key: 'form1[0].#subform[160].#field[289]' },
            'paymentRate' => { key: 'form1[0].#subform[160].Payment_Rate_Worked_Per_Week[0]' },
            'hoursPerWeek' => { key: 'form1[0].#subform[160].Hours_Worked_Per_Week[0]' },
            'startDate' => {
              'month' => { key: 'form1[0].#subform[160].Date_Month[18]' },
              'day' => { key: 'form1[0].#subform[160].Date_Day[18]' },
              'year' => { key: 'form1[0].#subform[160].Date_Year[18]' }
            },
            'endDate' => {
              'month' => { key: 'form1[0].#subform[160].Date_Month[17]' },
              'day' => { key: 'form1[0].#subform[160].Date_Day[17]' },
              'year' => { key: 'form1[0].#subform[160].Date_Year[17]' }
            },
            'noEndDate' => { key: 'form1[0].#subform[160].CheckBox_No_End_Date[0]' },
            'paymentAnnually' => { key: 'form1[0].#subform[160].Annually[0]' },
            'paymentMonthly' => { key: 'form1[0].#subform[160].Monthly[0]' },
            'paymentAmount' => { key: 'form1[0].#subform[160].VETERANS_SERVICE_NUMBER[5]' }
          },
          'careExpenseTwo' => {
            'recipientSurvivingSpouse' => { key: 'form1[0].#subform[161].#field[361]' },
            'recipientOther' => { key: 'form1[0].#subform[161].#field[362]' },
            'recipientName' => { key: 'form1[0].#subform[161].Other_Specify[1]' },
            'provider' => { key: 'form1[0].#subform[161].Name_Of_Provider_And_Type_Of_Care[1]' },
            'careNursingHome' => { key: 'form1[0].#subform[161].#field[403]' },
            'careResidential' => { key: 'form1[0].#subform[161].#field[404]' },
            'careAdultDayCare' => { key: 'form1[0].#subform[161].#field[402]' },
            'careInHomeCare' => { key: 'form1[0].#subform[161].#field[401]' },
            'paymentRate' => { key: 'form1[0].#subform[161].Payment_Rate_Worked_Per_Week[1]' },
            'hoursPerWeek' => { key: 'form1[0].#subform[161].Hours_Worked_Per_Week[1]' },
            'startDate' => {
              'month' => { key: 'form1[0].#subform[161].Date_Month[23]' },
              'day' => { key: 'form1[0].#subform[161].Date_Day[23]' },
              'year' => { key: 'form1[0].#subform[161].Date_Year[23]' }
            },
            'endDate' => {
              'month' => { key: 'form1[0].#subform[161].Date_Month[22]' },
              'day' => { key: 'form1[0].#subform[161].Date_Day[22]' },
              'year' => { key: 'form1[0].#subform[161].Date_Year[22]' }
            },
            'noEndDate' => { key: 'form1[0].#subform[161].CheckBox_No_End_Date[1]' },
            'paymentAnnually' => { key: 'form1[0].#subform[161].Checkboxno[7]' },
            'paymentMonthly' => { key: 'form1[0].#subform[161].Checkboxyes[8]' },
            'paymentAmount' => { key: 'form1[0].#subform[161].Account_Number[4]' }
          },
          'careExpenseThree' => {
            'recipientSurvivingSpouse' => { key: 'form1[0].#subform[161].#field[354]' },
            'recipientOther' => { key: 'form1[0].#subform[161].#field[353]' },
            'recipientName' => { key: 'form1[0].#subform[161].Other_Specify[0]' },
            'provider' => { key: 'form1[0].#subform[161].Name_Of_Provider_And_Type_Of_Care[2]' },
            'careNursingHome' => { key: 'form1[0].#subform[161].#field[414]' },
            'careResidential' => { key: 'form1[0].#subform[161].#field[415]' },
            'careAdultDayCare' => { key: 'form1[0].#subform[161].#field[412]' },
            'careInHomeCare' => { key: 'form1[0].#subform[161].#field[413]' },
            'paymentRate' => { key: 'form1[0].#subform[161].Payment_Rate_Worked_Per_Week[2]' },
            'hoursPerWeek' => { key: 'form1[0].#subform[161].Hours_Worked_Per_Week[2]' },
            'startDate' => {
              'month' => { key: 'form1[0].#subform[161].Date_Month[25]' },
              'day' => { key: 'form1[0].#subform[161].Date_Day[25]' },
              'year' => { key: 'form1[0].#subform[161].Date_Year[25]' }
            },
            'endDate' => {
              'month' => { key: 'form1[0].#subform[161].Date_Month[24]' },
              'day' => { key: 'form1[0].#subform[161].Date_Day[24]' },
              'year' => { key: 'form1[0].#subform[161].Date_Year[24]' }
            },

            'noEndDate' => { key: 'form1[0].#subform[161].CheckBox_No_End_Date[2]' },
            'paymentAnnually' => { key: 'form1[0].#subform[161].Checkboxno[6]' },
            'paymentMonthly' => { key: 'form1[0].#subform[161].Checkboxyes[7]' },
            'paymentAmount' => { key: 'form1[0].#subform[161].Account_Number[3]' }
          },
          'medicalExpenseOne' => {
            'surviving_spouse' => { key: 'form1[0].#subform[161].SURVIVING_SPOUSE[0]' },
            'veteran' => { key: 'form1[0].#subform[161].SURVIVING_SPOUSE[1]' },
            'child' => { key: 'form1[0].#subform[161].CHILD_Specify[0]' },
            'childName' => { key: 'form1[0].#subform[161].CHILD_EXPENSES[0]' },
            'provider' => { key: 'form1[0].#subform[161].Name_Of_Provider[0]' },
            'purpose' => { key: 'form1[0].#subform[161].PURPOSE[0]' },
            'monthly' => { key: 'form1[0].#subform[161].MONTHLY[0]' },
            'annually' => { key: 'form1[0].#subform[161].ANNUALLY[0]' },
            'oneTime' => { key: 'form1[0].#subform[161].ONE-TIME[0]' },
            'paymentDate' => {
              'month' => { key: 'form1[0].#subform[161].Date_Month[19]' },
              'day' => { key: 'form1[0].#subform[161].Date_Day[19]' },
              'year' => { key: 'form1[0].#subform[161].Date_Year[19]' }
            },
            'paymentAmount' => { key: 'form1[0].#subform[161].Account_Number[2]' }
          },
          'medicalExpenseTwo' => {
            'surviving_spouse' => { key: 'form1[0].#subform[161].SURVIVING_SPOUSE[2]' },
            'veteran' => { key: 'form1[0].#subform[161].SURVIVING_SPOUSE[3]' },
            'child' => { key: 'form1[0].#subform[161].CHILD_Specify[1]' },
            'childName' => { key: 'form1[0].#subform[161].CHILD_EXPENSES[1]' },
            'provider' => { key: 'form1[0].#subform[161].Name_Of_Provider[1]' },
            'purpose' => { key: 'form1[0].#subform[161].PURPOSE[1]' },
            'monthly' => { key: 'form1[0].#subform[161].MONTHLY[1]' },
            'annually' => { key: 'form1[0].#subform[161].ANNUALLY[1]' },
            'oneTime' => { key: 'form1[0].#subform[161].ONE-TIME[1]' },
            'paymentDate' => {
              'month' => { key: 'form1[0].#subform[161].Date_Month[20]' },
              'day' => { key: 'form1[0].#subform[161].Date_Day[20]' },
              'year' => { key: 'form1[0].#subform[161].Date_Year[20]' }
            },
            'paymentAmount' => { key: 'form1[0].#subform[161].Account_Number[1]' }
          },
          'medicalExpenseThree' => {
            'surviving_spouse' => { key: 'form1[0].#subform[161].SURVIVING_SPOUSE[4]' },
            'veteran' => { key: 'form1[0].#subform[161].SURVIVING_SPOUSE[5]' },
            'child' => { key: 'form1[0].#subform[161].CHILD_Specify[2]' },
            'childName' => { key: 'form1[0].#subform[161].CHILD_EXPENSES[2]' },
            'provider' => { key: 'form1[0].#subform[161].Name_Of_Provider[2]' },
            'purpose' => { key: 'form1[0].#subform[161].PURPOSE[2]' },
            'monthly' => { key: 'form1[0].#subform[161].MONTHLY[2]' },
            'annually' => { key: 'form1[0].#subform[161].ANNUALLY[2]' },
            'oneTime' => { key: 'form1[0].#subform[161].ONE-TIME[2]' },
            'paymentDate' => {
              'month' => { key: 'form1[0].#subform[161].Date_Month[21]' },
              'day' => { key: 'form1[0].#subform[161].Date_Day[21]' },
              'year' => { key: 'form1[0].#subform[161].Date_Year[21]' }
            },
            'paymentAmount' => { key: 'form1[0].#subform[161].Account_Number[0]' }
          },
          'medicalExpenseFour' => {
            'surviving_spouse' => { key: 'form1[0].#subform[162].SURVIVING_SPOUSE[6]' },
            'veteran' => { key: 'form1[0].#subform[162].SURVIVING_SPOUSE[7]' },
            'child' => { key: 'form1[0].#subform[162].CHILD_Specify[3]' },
            'childName' => { key: 'form1[0].#subform[162].CHILD_EXPENSES[3]' },
            'provider' => { key: 'form1[0].#subform[162].Name_Of_Provider[4]' },
            'purpose' => { key: 'form1[0].#subform[162].PURPOSE[4]' },
            'monthly' => { key: 'form1[0].#subform[162].MONTHLY[5]' },
            'annually' => { key: 'form1[0].#subform[162].ANNUALLY[5]' },
            'oneTime' => { key: 'form1[0].#subform[162].RadioButtonList[29]' },
            'paymentDate' => {
              'month' => { key: 'form1[0].#subform[162].Date_Month[28]' },
              'day' => { key: 'form1[0].#subform[162].Date_Day[28]' },
              'year' => { key: 'form1[0].#subform[162].Date_Year[28]' }
            },
            'paymentAmount' => { key: 'form1[0].#subform[162].Account_Number[8]' }
          },
          'medicalExpenseFive' => {
            'surviving_spouse' => { key: 'form1[0].#subform[162].SURVIVING_SPOUSE[8]' },
            'veteran' => { key: 'form1[0].#subform[162].SURVIVING_SPOUSE[9]' },
            'child' => { key: 'form1[0].#subform[162].CHILD_Specify[4]' },
            'childName' => { key: 'form1[0].#subform[162].CHILD_EXPENSES[4]' },
            'provider' => { key: 'form1[0].#subform[162].Name_Of_Provider[5]' },
            'purpose' => { key: 'form1[0].#subform[162].PURPOSE[5]' },
            'monthly' => { key: 'form1[0].#subform[162].MONTHLY[3]' },
            'annually' => { key: 'form1[0].#subform[162].ANNUALLY[3]' },
            'oneTime' => { key: 'form1[0].#subform[162].ONE-TIME[3]' },
            'paymentDate' => {
              'month' => { key: 'form1[0].#subform[162].Date_Month[26]' },
              'day' => { key: 'form1[0].#subform[162].Date_Day[26]' },
              'year' => { key: 'form1[0].#subform[162].Date_Year[26]' }
            },
            'paymentAmount' => { key: 'form1[0].#subform[162].Account_Number[6]' }
          },
          'medicalExpenseSixth' => {
            'surviving_spouse' => { key: 'form1[0].#subform[162].SURVIVING_SPOUSE[10]' },
            'veteran' => { key: 'form1[0].#subform[162].VETERAN[0]' },
            'child' => { key: 'form1[0].#subform[162].CHILD_Specify[5]' },
            'childName' => { key: 'form1[0].#subform[162].CHILD_EXPENSES[5]' },
            'provider' => { key: 'form1[0].#subform[162].Name_Of_Provider[3]' },
            'purpose' => { key: 'form1[0].#subform[162].PURPOSE[3]' },
            'monthly' => { key: 'form1[0].#subform[162].MONTHLY[4]' },
            'annually' => { key: 'form1[0].#subform[162].ANNUALLY[4]' },
            'oneTime' => { key: 'form1[0].#subform[162].ONE-TIME[4]' },
            'paymentDate' => {
              'month' => { key: 'form1[0].#subform[162].Date_Month[27]' },
              'day' => { key: 'form1[0].#subform[162].Date_Day[27]' },
              'year' => { key: 'form1[0].#subform[162].Date_Year[27]' }
            },
            'paymentAmount' => { key: 'form1[0].#subform[162].Account_Number[7]' }
          }
        }.freeze
        def expand(form_data = {})
          form_data['p16HeaderVeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])
          form_data['anythingToReportYes'] =
            form_data['careExpenses'].present? || form_data['medicalExpenses'].present? ? '1' : 'Off'
          form_data['anythingToReportNo'] =
            form_data['careExpenses'].blank? && form_data['medicalExpenses'].blank? ? '1' : 'Off'

          expand_care_expenses(form_data)
          expand_medical_expenses(form_data)

          form_data
        end

        private

        def expand_care_expenses(form_data)
          form_data['careExpenses'] ||= []
          care_expenses = form_data['careExpenses'].map { |expense| expand_care_expense(expense) }
          form_data['careExpenseOne'] = care_expenses.first || {}
          form_data['careExpenseTwo'] = care_expenses.second || {}
          form_data['careExpenseThree'] = care_expenses.third || {}
        end

        def expand_medical_expenses(form_data)
          form_data['medicalExpenses'] ||= []
          medical_expenses = form_data['medicalExpenses']
                             .each_with_index
                             .map { |expense, index| expand_medical_expense(expense, index) }
          form_data['medicalExpenseOne'] = medical_expenses[0] || {}
          form_data['medicalExpenseTwo'] = medical_expenses[1] || {}
          form_data['medicalExpenseThree'] = medical_expenses[2] || {}
          form_data['medicalExpenseFour'] = medical_expenses[3] || {}
          form_data['medicalExpenseFive'] = medical_expenses[4] || {}
          form_data['medicalExpenseSixth'] = medical_expenses[5] || {}
        end

        def expand_care_expense(expense = {})
          care_type = expense['careType']

          expense.merge({
                          'recipientSurvivingSpouse' => expense['recipient'] == 'SURVIVING_SPOUSE' ? '1' : '',
                          'recipientOther' => expense['recipient'] == 'OTHER' ? '1' : '',
                          'recipientName' => expense['recipientName'],
                          'provider' => expense['provider'],
                          'careNursingHome' => care_type == 'NURSING_HOME' ? '1' : '',
                          'careResidential' => care_type == 'RESIDENTIAL_CARE' ? '1' : '',
                          'careAdultDayCare' => care_type == 'CARE_FACILITY' ? '1' : '',
                          'careInHomeCare' => care_type == 'IN_HOME_CARE_ATTENDANT' ? '1' : '',
                          'startDate' => split_date(expense.dig('careDateRange', 'from')),
                          'endDate' => split_date(expense.dig('careDateRange', 'to')),
                          'paymentRate' => expense['ratePerHour'],
                          'hoursPerWeek' => expense['hoursPerWeek'],
                          'paymentAnnually' => expense['paymentFrequency'] == 'ANNUALLY' ? '1' : '',
                          'paymentMonthly' => expense['paymentFrequency'] == 'MONTHLY' ? '1' : '',
                          'paymentAmount' => expense['paymentAmount'],
                          'noEndDate' => expense['noCareEndDate'] ? '1' : ''
                        })
        end

        def expand_medical_expense(expense = {}, index = nil)
          recipient = expense['recipients'] || expense['recipient']
          expense.merge({
                          'surviving_spouse' => recipient == 'SURVIVING_SPOUSE' ? '1' : '',
                          'veteran' => recipient == 'VETERAN' ? '1' : '',
                          'child' => recipient == 'CHILD' ? '1' : '',
                          'childName' => expense['childName'],
                          'provider' => expense['provider'],
                          'purpose' => expense['purpose'],
                          'paymentDate' => split_date(expense['paymentDate']),
                          'monthly' => expense['paymentFrequency'] == 'MONTHLY' ? '1' : '',
                          'annually' => expense['paymentFrequency'] == 'ANNUALLY' ? '1' : '',
                          'oneTime' => expense['paymentFrequency'] == 'ONE_TIME' ? correct_one_time(index) : '',
                          'paymentAmount' => expense['paymentAmount']
                        })
        end

        # The 4th ONE TIME medical expense field uses a 3 instead of 1 as the on value.
        def correct_one_time(index = nil)
          if index == 3
            '3'
          else
            '1'
          end
        end
      end
    end
  end
end
