# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section I: Veteran Information
    class Section1V2 < Section
      # Section configuration hash
      KEY = {
        # 1a
        'veteranFullName' => {
          'first' => {
            limit: 12,
            question_num: 1,
            question_suffix: 'A',
            question_label: "Veteran's First Name",
            question_text: "VETERAN'S FIRST NAME",
            key: 'veteran_first_name'
          },
          'middle' => {
            key: 'veteran_middle_name'
          },
          'last' => {
            limit: 18,
            question_num: 1,
            question_suffix: 'A',
            question_label: "Veteran's Last Name",
            question_text: "VETERAN'S LAST NAME",
            key: 'veteran_last_name'
          }
        },
        # 1b
        'veteranSocialSecurityNumber' => {
          'first' => {
            key: 'veteran_ssn_1'
          },
          'second' => {
            key: 'veteran_ssn_2'
          },
          'third' => {
            key: 'veteran_ssn_3'
          }
        },
        # 1c
        'veteranDateOfBirth' => {
          'month' => {
            key: 'veteran_dob_month'
          },
          'day' => {
            key: 'veteran_dob_day'
          },
          'year' => {
            key: 'veteran_dob_year'
          }
        },
        # 1d
        'vaClaimsHistory' => {
          key: 'va_claim_history'
        },
        # 1e
        'vaFileNumber' => {
          key: 'va_file_number'
        }
      }.freeze

      ##
      # Expands and normalizes the veteran's information
      #
      # @param form_data [Hash]
      #
      # @note Modifies `form_data`
      #
      def expand(form_data)
        form_data.merge!(
          {
            'veteranFullName' => expand_full_name(form_data['veteranFullName']),
            'veteranSocialSecurityNumber' => split_ssn(form_data['veteranSocialSecurityNumber']),
            'veteranDateOfBirth' => split_date(form_data['veteranDateOfBirth']),
            'vaClaimsHistory' => to_radio_yes_no(form_data['vaClaimsHistory'])
          }
        )
        # If "NO" to 1d, skip 1e
        form_data.delete('vaFileNumber') unless yes?(form_data['vaClaimsHistory'])
      end
    end
  end
end
