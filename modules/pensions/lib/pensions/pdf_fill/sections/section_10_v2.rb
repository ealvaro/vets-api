# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section X: Information about your unreimbursed medical expenses
    class Section10V2 < Section
      # Section configuration hash
      KEY = {
        # 10a
        'hasAnyExpenses' => {
          key: 'has_any_expenses'
        },
        # 10b-d Care Expenses
        'careExpenses' => {
          limit: 3,
          item_label: 'Care expense',
          first_key: 'childName',
          # (1) Recipient
          'recipients' => {
            key: "care_recipient[#{ITERATOR}]"
          },
          'recipientsOverflow' => {
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Care Expense Recipient',
            question_text: 'CARE EXPENSE RECIPIENT'
          },
          'childName' => {
            key: "care_dependent_name[#{ITERATOR}]",
            limit: 19,
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Care Expense Child Name',
            question_text: 'CARE EXPENSE CHILD NAME'
          },
          # (2) Provider
          'provider' => {
            key: "care_provider[#{ITERATOR}]",
            limit: 87,
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Care Expense Provider Name',
            question_text: 'CARE EXPENSE PROVIDER NAME'
          },
          # (3) Type of Care
          'careType' => {
            key: "care_type[#{ITERATOR}]"
          },
          'careTypeOverflow' => {
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Care Type',
            question_text: 'CARE TYPE'
          },
          # (4) Rate Per Hour
          'ratePerHour' => {
            key: "care_hourly_rate[#{ITERATOR}]",
            limit: 10,
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Care Expense Rate Per Hour',
            question_text: 'CARE EXPENSE RATE PER HOUR',
            dollar: true
          },
          # (5) Hours Per Week
          'hoursPerMonth' => {
            limit: 3,
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Provider Hours Worked Per Month',
            question_text: 'PROVIDER HOURS WORKED PER MONTH',
            key: "care_monthly_hours[#{ITERATOR}]"
          },
          # (6-7) Provider Start/End Dates
          'careDateRange' => {
            'from' => {
              'month' => {
                key: "care_start_date_month[#{ITERATOR}]"
              },
              'day' => {
                key: "care_start_date_day[#{ITERATOR}]"
              },
              'year' => {
                key: "care_start_date_year[#{ITERATOR}]"
              }
            },
            'to' => {
              'month' => {
                key: "care_end_date_month[#{ITERATOR}]"
              },
              'day' => {
                key: "care_end_date_day[#{ITERATOR}]"
              },
              'year' => {
                key: "care_end_date_year[#{ITERATOR}]"
              }
            }
          },
          'careDateRangeOverflow' => {
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Date Range Care Received',
            question_text: 'DATE RANGE CARE RECEIVED'
          },
          'noCareEndDate' => {
            key: "no_care_date_end[#{ITERATOR}]"
          },
          # (8) Payment Frequency
          'paymentFrequency' => {
            key: "care_payment_frequency[#{ITERATOR}]"
          },
          'paymentFrequencyOverflow' => {
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Care Expense Payment Frequency',
            question_text: 'CARE EXPENSE PAYMENT FREQUENCY'
          },
          # (9) Payment Amount
          'paymentAmount' => {
            key: "care_payment_amount[#{ITERATOR}]",
            limit: 10,
            question_num: 10,
            question_suffix: 'A',
            question_label: 'Care Expense Payment Amount',
            question_text: 'CARE EXPENSE PAYMENT AMOUNT',
            dollar: true
          }
        },
        # 10e-j Medical Expenses
        'medicalExpenses' => {
          limit: 6,
          item_label: 'Medical expense',
          first_key: 'childName',
          # (1) Recipient
          'recipients' => {
            key: "medical_recipient[#{ITERATOR}]"
          },
          'recipientsOverflow' => {
            question_num: 10,
            question_suffix: 'B',
            question_label: 'Medical Expense Recipient',
            question_text: 'MEDICAL EXPENSE RECIPIENT'
          },
          'childName' => {
            key: "medical_dependent_name[#{ITERATOR}]",
            limit: 34,
            question_num: 10,
            question_suffix: 'B',
            question_label: 'Medical Expense Child Name',
            question_text: 'MEDICAL EXPENSE CHILD NAME'
          },
          # (2) Provider
          'provider' => {
            key: "medical_provider[#{ITERATOR}]",
            limit: 132,
            question_num: 10,
            question_suffix: 'B',
            question_label: 'Medical Expense Provider Name',
            question_text: 'MEDICAL EXPENSE PROVIDER NAME'
          },
          # (3) Purpose
          'purpose' => {
            key: "medical_purpose[#{ITERATOR}]",
            limit: 99,
            question_num: 10,
            question_suffix: 'B',
            question_label: 'Medical Expense Purpose',
            question_text: 'MEDICAL EXPENSE PURPOSE'
          },
          # (4) Payment Date
          'paymentDate' => {
            'month' => {
              key: "medical_pay_date_month[#{ITERATOR}]"
            },
            'day' => {
              key: "medical_pay_date_day[#{ITERATOR}]"
            },
            'year' => {
              key: "medical_pay_date_year[#{ITERATOR}]"
            }
          },
          'paymentDateOverflow' => {
            question_num: 10,
            question_suffix: 'B',
            question_label: 'Medical Expense Payment Date',
            question_text: 'MEDICAL EXPENSE PAYMENT DATE'
          },
          # (5) Payment Frequency
          'paymentFrequency' => {
            key: "medical_payment_frequency[#{ITERATOR}]"
          },
          'paymentFrequencyOverflow' => {
            question_num: 10,
            question_suffix: 'B',
            question_label: 'Medical Expense Payment Frequency',
            question_text: 'MEDICAL EXPENSE PAYMENT FREQUENCY'
          },
          # (6) Rate Per Frequency
          'paymentAmount' => {
            key: "medical_payment_amount[#{ITERATOR}]",
            limit: 9,
            question_num: 10,
            question_suffix: 'B',
            question_label: 'Medical Expense Payment Amount',
            question_text: 'MEDICAL EXPENSE PAYMENT AMOUNT',
            dollar: true
          }
        }
      }.freeze

      ##
      # Expands the medical and care expenses information by:
      # - Converting hasAnyExpenses to radio button format
      # - Merging care expenses data
      # - Merging medical expenses data
      #
      # @param form_data [Hash] the form data hash to be expanded
      #
      # @return [void]
      #
      # @note Modifies `form_data`
      #
      def expand(form_data)
        any_expenses = form_data['careExpenses']&.any? || form_data['medicalExpenses']&.any? || false
        form_data['hasAnyExpenses'] = to_radio_yes_no(any_expenses)
        return unless yes?(form_data['hasAnyExpenses'])

        expand_expenses(form_data['careExpenses'], care_expense: true)
        expand_expenses(form_data['medicalExpenses'])
      end

      ##
      # Iterates over and expands an array of expense hashes (either care or medical).
      #
      # @param expenses [Array<Hash>, nil] the list of expense records
      # @param care_expense [Boolean] flag indicating if the expenses are care expenses
      #
      # @return [void]
      #
      # @note Modifies each expense hash in place
      #
      def expand_expenses(expenses, care_expense: false)
        expenses&.each do |expense|
          expense.merge!({
                           'recipients' => RECIPIENTS[expense['recipients']],
                           'recipientsOverflow' => expense['recipients']&.humanize,
                           'paymentFrequency' => PAYMENT_FREQUENCY[expense['paymentFrequency']],
                           'paymentFrequencyOverflow' => expense['paymentFrequency'],
                           'paymentAmount' => expand_currency(expense['paymentAmount'])
                         })
          if care_expense
            expand_care_expense(expense)
          else
            expense['paymentDate'] = split_date(expense['paymentDate'])
          end
        end
      end

      ##
      # Expands a single care expense data hash with specific care-related fields.
      #
      # @param expense [Hash] the care expense hash to expand
      #
      # @return [void]
      #
      # @note Modifies the expense hash in place
      #
      def expand_care_expense(expense)
        no_end_date = if expense['noCareEndDate'].nil?
                        expense.dig('careDateRange', 'to').blank? || false
                      else
                        expense['noCareEndDate']
                      end
        expense.merge!({
                         'careType' => CARE_TYPES_V2[expense['careType']],
                         'careTypeOverflow' => expense['careType']&.humanize,
                         'ratePerHour' => expand_currency(expense['ratePerHour']),
                         # TODO: Remove 'hoursPerWeek' backward compatibility after form migration complete
                         'hoursPerMonth' => expense['hoursPerMonth'].presence || expense['hoursPerWeek'],
                         'careDateRange' => {
                           'from' => split_date(expense.dig('careDateRange', 'from')),
                           'to' => split_date(expense.dig('careDateRange', 'to'))
                         },
                         'noCareEndDate' => to_checkbox_on_off(no_end_date),
                         'careDateRangeOverflow' => build_date_range_string(expense['careDateRange'])
                       })
      end
    end
  end
end
