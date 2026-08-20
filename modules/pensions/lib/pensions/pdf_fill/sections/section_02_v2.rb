# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section II: Veteran's Contact Information
    class Section2V2 < Section
      # Character limit for street
      STREET_LIMIT = 30
      # Character limit for street2
      STREET_2_LIMIT = 5

      # Section configuration hash
      KEY = {
        # 2a
        'veteranAddress' => {
          'street' => {
            limit: STREET_LIMIT,
            question_num: 2,
            question_suffix: 'A',
            question_label: 'Mailing Address Number And Street',
            question_text: 'MAILING ADDRESS NUMBER AND STREET',
            key: 'street_1',
            hide_from_overflow: true
          },
          'street2' => {
            limit: STREET_2_LIMIT,
            question_num: 2,
            question_suffix: 'A',
            question_label: 'Mailing Address Apt/Unit',
            question_text: 'MAILING ADDRESS APT/UNIT',
            key: 'street_2',
            hide_from_overflow: true
          },
          'street3' => {
            limit: 0,
            question_num: 2,
            question_suffix: 'A',
            question_label: 'Mailing Address Street',
            question_text: 'MAILING ADDRESS STREET',
            key: 'street_1'
          },
          'city' => {
            limit: 18,
            question_num: 2,
            question_suffix: 'A',
            question_label: 'Mailing Address City',
            question_text: 'MAILING ADDRESS CITY',
            key: 'city'
          },
          'state' => {
            key: 'state'
          },
          'country' => {
            key: 'country'
          },
          'postalCode' => {
            'firstFive' => {
              key: 'postal_code_1'
            },
            'lastFour' => {
              limit: 4,
              question_num: 2,
              question_suffix: 'A',
              question_label: 'Postal Code - Last Four',
              question_text: 'POSTAL CODE - LAST FOUR',
              key: 'postal_code_2'
            }
          }
        },
        # 2b
        'mobilePhone' => {
          'phone_area_code' => {
            key: 'phone_1'
          },
          'phone_first_three_numbers' => {
            key: 'phone_2'
          },
          'phone_last_four_numbers' => {
            key: 'phone_3'
          }
        },
        'internationalPhone' => {
          limit: 26,
          question_num: 2,
          question_suffix: 'C',
          question_label: 'International Phone Number',
          question_text: 'International Phone Number',
          key: 'international_phone'
        },
        # 2c
        'email' => {
          limit: 52,
          question_num: 2,
          question_suffix: 'C',
          question_label: "Veteran's E-Mail Address",
          question_text: 'VETERAN\'S E-MAIL ADDRESS',
          key: 'email'
        }
      }.freeze

      ##
      # Expand the form data for Veteran contact information
      #
      # @param form_data [Hash] The form data hash
      #
      # @return [void]
      #
      # Note: This method modifies `form_data`
      #
      def expand(form_data)
        address = form_data['veteranAddress']
        form_data.deep_merge!(
          {
            'veteranAddress' => {
              'postalCode' => split_postal_code(address),
              'country' => address['country']&.slice(0, 2)
            },
            'mobilePhone' => expand_phone_number(form_data['mobilePhone'])
          }
        )
        handle_street_overflow(form_data['veteranAddress'], STREET_LIMIT, STREET_2_LIMIT)
      end
    end
  end
end
