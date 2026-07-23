# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section VI: Marital Status
    class Section6V2 < Section
      # Character limit for location of current marriage city
      CITY_CHAR_LIMIT = 18

      # Section configuration hash
      KEY = {
        # 6a
        'maritalStatus' => {
          key: 'marital_status'
        },
        'currentSpouse' => {
          # 6b
          'spouseFullName' => {
            'first' => {
              limit: 12,
              question_num: 6,
              question_suffix: 'B',
              question_label: "Current Spouse's First Name",
              question_text: 'CURRENT SPOUSE\'S FIRST NAME',
              key: 'current_spouse_first_name'
            },
            'middle' => {
              key: 'current_spouse_middle_name'
            },
            'last' => {
              limit: 18,
              question_num: 6,
              question_suffix: 'B',
              question_label: "Current Spouse's Last Name",
              question_text: 'CURRENT SPOUSE\'S LAST NAME',
              key: 'current_spouse_last_name'
            }
          },
          # 6e
          'dateOfMarriage' => {
            'month' => {
              key: 'current_spouse_marriage_date_month'
            },
            'day' => {
              key: 'current_spouse_marriage_date_day'
            },
            'year' => {
              key: 'current_spouse_marriage_date_year'
            }
          },
          'locationOfMarriage' => {
            # 6f
            'city' => {
              limit: CITY_CHAR_LIMIT,
              question_num: 6,
              question_suffix: 'F',
              question_label: 'Place of Marriage City',
              question_text: 'PLACE OF MARRAIGE CITY',
              key: 'marriage_location_city'
            },
            # 6g
            'state' => {
              limit: 2,
              question_num: 6,
              question_suffix: 'G',
              question_label: 'Place of Marriage State',
              question_text: 'PLACE OF MARRAIGE STATE',
              key: 'marriage_location_state'
            },
            # 6h
            'country' => {
              limit: 3,
              question_num: 6,
              question_suffix: 'H',
              question_label: 'Place of Marriage Country',
              question_text: 'PLACE OF MARRAIGE COUNTRY',
              key: 'marriage_location_country'
            }
          },
          'locationOfMarriageOverflow' => {
            limit: 0,
            question_num: 6,
            question_suffix: 'F-H',
            question_label: 'Place of Marriage City and State or Country',
            question_text: 'PLACE OF MARRIAGE CITY AND STATE OR COUNTRY',
            key: 'marriage_location_city'
          },
          # 6i
          'marriageType' => {
            key: 'marriage_type'
          },
          'otherExplanation' => {
            limit: 33,
            question_num: 6,
            question_suffix: 'I',
            question_label: 'Specify Type Of Marriage',
            question_text: 'SPECIFY TYPE OF MARRIAGE',
            key: 'marriage_type_other'
          }
        },
        # 6c
        'spouseDateOfBirth' => {
          'month' => {
            key: 'current_spouse_dob_month'
          },
          'day' => {
            key: 'current_spouse_dob_day'
          },
          'year' => {
            key: 'current_spouse_dob_year'
          }
        },
        # 6d
        'spouseSocialSecurityNumber' => {
          'first' => {
            key: 'current_spouse_ssn_1'
          },
          'second' => {
            key: 'current_spouse_ssn_2'
          },
          'third' => {
            key: 'current_spouse_ssn_3'
          }
        },
        # 6j
        'spouseIsVeteran' => {
          key: 'spouse_is_veteran'
        },
        # 6k
        'spouseVaFileNumber' => {
          key: 'current_spouse_va_file_number'
        },
        # 6l
        'reasonForCurrentSeparation' => {
          key: 'current_spouse_separation_reason'
        },
        'otherExplanation' => {
          limit: 39,
          question_num: 6,
          question_suffix: 'L',
          question_label: 'Specify reason you are separated',
          question_text: 'SPECIFY REASON YOU ARE SEPARATED',
          key: 'separation_reason_other'
        },
        # 6m
        'spouseAddress' => {
          'street' => {
            limit: 30,
            question_num: 6,
            question_suffix: 'M',
            question_label: 'Spouse Mailing Address Street',
            question_text: 'SPOUSE MAILING ADDRESS STREET',
            key: 'spouse_street_1'
          },
          'street2' => {
            limit: 5,
            question_num: 6,
            question_suffix: 'M',
            question_label: 'Spouse Mailing Address Apt Number',
            question_text: 'SPOUSE MAILING ADDRESS APT NUMBER',
            key: 'spouse_street_2'
          },
          'city' => {
            limit: 18,
            question_num: 6,
            question_suffix: 'J',
            question_label: 'Spouse Mailing Address City',
            question_text: 'SPOUSE MAILING ADDRESS CITY',
            key: 'spouse_city'
          },
          'state' => {
            key: 'spouse_state'
          },
          'country' => {
            key: 'spouse_country'
          },
          'postalCode' => {
            'firstFive' => {
              key: 'spouse_postal_code_1'
            },
            'lastFour' => {
              key: 'spouse_postal_code_2'
            }
          }
        },
        # 6k
        'currentSpouseMonthlySupport' => {
          limit: 8,
          question_num: 6,
          question_suffix: 'K',
          question_label: 'Spouse Monthly Support',
          question_text: 'SPOUSE MONTHLY_SUPPORT',
          key: 'spouse_monthly_support',
          dollar: true
        }
      }.freeze

      ##
      # Expand the form data for current marital status
      #
      # @param form_data [Hash] The form data hash
      #
      # @return [Hash, nil]
      #
      # @note This method modifies `form_data`
      #
      def expand(form_data)
        form_data['maritalStatus'] = MARITAL_STATUS[form_data['maritalStatus']]
        return if skip_when_not_married?(form_data)

        expand_current_spouse(form_data['currentSpouse'])
        expand_spouse_attributes(form_data)
        expand_spouse_address(form_data['spouseAddress'])
        form_data['currentSpouseMonthlySupport'] = expand_currency(form_data['currentSpouseMonthlySupport'])
      end

      private

      ##
      # Skip section unless married or separated and clean up unused keys
      #
      # @param form_data [Hash] The form data hash
      #
      # @return [Boolean] True if skipped, false otherwise
      #
      # @note This method modifies `form_data` by removing spouse keys if not married
      #
      def skip_when_not_married?(form_data)
        return false if yes?(form_data['maritalStatus'], MARITAL_STATUS.values_at('MARRIED', 'SEPARATED'))

        spouse_keys = KEY.keys - ['maritalStatus']

        form_data.except!(*spouse_keys)

        true
      end

      ##
      # Expand the current marriage details
      #
      # @param spouse [Hash] The spouse hash
      #
      # @return [Hash, nil]
      #
      # @note This method modifies the `spouse` hash in place
      #
      def expand_current_spouse(spouse)
        return if spouse.blank?

        spouse.merge!(
          {
            'spouseFullName' => expand_full_name(spouse['spouseFullName']),
            'marriageType' => MARRIAGE_TYPE.fetch(spouse['marriageType'], MARRIAGE_TYPE['OTHER']),
            'dateOfMarriage' => split_date(spouse['dateOfMarriage'])
          }
        )
        expand_marriage_location(spouse)
      end

      ##
      # Expand the marriage location and handle overflow formatting if necessary
      #
      # @param spouse [Hash] The spouse hash
      #
      # @return [Hash, String, nil] The updated location or overflow string
      #
      # @note This method modifies the `spouse` hash in place
      #
      def expand_marriage_location(spouse)
        spouse['locationOfMarriage'] = expand_location(spouse['locationOfMarriage'])
        # Overflow if location is a string and not an expanded hash
        if spouse['locationOfMarriage'].is_a?(String)
          spouse['locationOfMarriageOverflow'] = spouse.delete('locationOfMarriage')
        end
      end

      # Splits city from state or country code
      # example: "Austin, TX" or "Calgary, CAN"
      LOCATION_REGEX = /^(.+),\s*([a-z]{2,3})$/i

      ##
      # Parse location string for city, state, and country components
      #
      # @param location [String] The raw location string
      #
      # @return [Hash, String, nil] Expanded location hash, or original string if unparseable
      #
      def expand_location(location = '')
        matches = location.match(LOCATION_REGEX)&.captures
        return location if matches.nil?

        city, state_or_country = matches
        return location if city.length > CITY_CHAR_LIMIT || !state_or_country.length.between?(2, 3)

        domestic = state_or_country.length == 2
        {
          'city' => city,
          'state' => (state_or_country if domestic),
          'country' => (domestic ? 'USA' : state_or_country)
        }.compact
      end

      ##
      # Expand additional spouse attributes and handle veteran VA file number cleanup
      #
      # @param form_data [Hash] The form data hash
      #
      # @return [Hash]
      #
      # @note This method modifies `form_data` in place
      #
      def expand_spouse_attributes(form_data)
        form_data.merge!(
          {
            'spouseDateOfBirth' => split_date(form_data['spouseDateOfBirth']),
            'spouseSocialSecurityNumber' => split_ssn(form_data['spouseSocialSecurityNumber']),
            'spouseIsVeteran' => to_radio_yes_no(form_data['spouseIsVeteran']),
            'reasonForCurrentSeparation' => REASON_FOR_SEPARATION.fetch(form_data['reasonForCurrentSeparation'], 'Off')
          }
        )
        # Skip 6K if spouse not a veteran
        form_data.delete('spouseVaFileNumber') unless yes?(form_data['spouseIsVeteran'])
      end

      ##
      # Expand spouse's mailing address postal codes and country code formatting
      #
      # @param address [Hash] The address hash
      #
      # @return [Hash, nil]
      #
      # @note This method modifies the `address` hash in place
      #
      def expand_spouse_address(address)
        return if address.blank?

        address.merge!(
          {
            'postalCode' => split_postal_code(address),
            'country' => address['country']&.slice(0, 2)
          }
        )
      end
    end
  end
end
