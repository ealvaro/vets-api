# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section VIII: Dependent Children
    class Section8V2 < Section
      # Section configuration hash
      KEY = {
        # 8a
        'dependentChildrenInHousehold' => {
          limit: 2,
          key: 'dependent_children_in_household'
        },
        # 8b-p dependent children
        'dependents' => {
          limit: 3,
          first_key: 'childPlaceOfBirth',
          item_label: 'Child',
          # 8b
          'fullName' => {
            'first' => {
              limit: 12,
              question_num: 8,
              question_label: "Child's First Name",
              question_text: 'CHILD\'S FIRST NAME',
              key: "child_first_name[#{ITERATOR}]"
            },
            'middle' => {
              question_num: 8,
              question_label: "Child's Middle Name",
              question_text: 'CHILD\'S MIDDLE NAME',
              key: "child_middle_name[#{ITERATOR}]"
            },
            'last' => {
              limit: 18,
              question_num: 8,
              question_label: "Child's Last Name",
              question_text: 'CHILD\'S LAST NAME',
              key: "child_last_name[#{ITERATOR}]"
            }
          },
          # 8c
          'childDateOfBirth' => {
            'month' => {
              key: "child_dob_month[#{ITERATOR}]"
            },
            'day' => {
              key: "child_dob_day[#{ITERATOR}]"
            },
            'year' => {
              key: "child_dob_year[#{ITERATOR}]"
            }
          },
          'childDateOfBirthOverflow' => {
            question_num: 8,
            question_label: "Child's Date Of Birth",
            question_text: 'CHILD\'S DATE OF BIRTH'
          },
          # 8d
          'childSocialSecurityNumber' => {
            'first' => {
              key: "child_ssn_1[#{ITERATOR}]"
            },
            'second' => {
              key: "child_ssn_2[#{ITERATOR}]"
            },
            'third' => {
              key: "child_ssn_3[#{ITERATOR}]"
            }
          },
          'childSocialSecurityNumberOverflow' => {
            question_num: 8,
            question_label: "Child's Social Security Number",
            question_text: 'CHILD\'S SOCIAL SECURITY NUMBER'
          },
          # 8e
          'childPlaceOfBirth' => {
            limit: 50,
            question_num: 8,
            question_label: "Child's Place Of Birth",
            question_text: 'CHILD\'S PLACE OF BIRTH',
            key: "child_place_of_birth[#{ITERATOR}]"
          },
          # 8F
          'childRelationship' => {
            'biological' => {
              key: "child_biological[#{ITERATOR}]"
            },
            'adopted' => {
              key: "child_adopted[#{ITERATOR}]"
            },
            'stepchild' => {
              key: "child_stepchild[#{ITERATOR}]"
            }
          },
          'disabled' => {
            key: "child_disabled[#{ITERATOR}]"
          },
          'attendingCollege' => {
            key: "child_attending_college[#{ITERATOR}]"
          },
          'previouslyMarried' => {
            key: "child_married[#{ITERATOR}]"
          },
          'childNotInHousehold' => {
            key: "child_not_in_household[#{ITERATOR}]"
          },
          'childStatusOverflow' => {
            question_num: 8,
            question_label: "Child's Status",
            question_text: 'CHILD\'S STATUS'
          },
          'monthlyPayment' => {
            limit: 9,
            question_num: 8,
            question_suffix: 'F',
            question_label: 'Annual Contribution To Child',
            question_text: 'ANNUAL CONTRIBUTUION TO CHILD',
            key: "child_monthly_payment[#{ITERATOR}]",
            dollar: true
          }
        },
        # 8q
        'dependentsNotWithYouAtSameAddress' => {
          key: 'children_not_at_same_address'
        },
        # 8r
        'custodians' => {
          limit: 1,
          first_key: 'first',
          'first' => {
            limit: 12,
            key: "custodian_first_name[#{ITERATOR}]",
            question_num: 8,
            question_suffix: 'R',
            question_label: "Custodian's First Name",
            question_text: 'CUSTODIAN\'S FIRST NAME'
          },
          'middle' => {
            key: "custodian_middle_name[#{ITERATOR}]"
          },
          'last' => {
            limit: 18,
            key: "custodian_last_name[#{ITERATOR}]",
            question_num: 8,
            question_suffix: 'R',
            question_label: "Custodian's Last Name",
            question_text: 'CUSTODIAN\'S LAST NAME'
          },
          'custodianAddress' => {
            'street' => {
              limit: 30,
              key: "custodian_street_1[#{ITERATOR}]"
            },
            'street2' => {
              limit: 5,
              key: "custodian_street_2[#{ITERATOR}]"
            },
            'city' => {
              limit: 18,
              key: "custodian_city[#{ITERATOR}]"
            },
            'state' => {
              key: "custodian_state[#{ITERATOR}]"
            },
            'country' => {
              key: "custodian_country[#{ITERATOR}]"
            },
            'postalCode' => {
              'firstFive' => {
                key: "custodian_postal_code_1[#{ITERATOR}]"
              },
              'lastFour' => {
                key: "custodian_postal_code_2[#{ITERATOR}]"
              }
            }
          },
          'custodianAddressOverflow' => {
            question_num: 8,
            question_suffix: 'R',
            question_label: "Custodian's Address",
            question_text: 'CUSTODIAN\'S ADDRESS'
          },
          'dependentsWithCustodianOverflow' => {
            question_num: 8,
            question_suffix: 'R',
            question_label: 'Dependents Living With This Custodian',
            question_text: 'DEPENDENTS LIVING WITH THIS CUSTODIAN'
          }
        }
      }.freeze

      ##
      # Expands dependent children section
      #
      # @param form_data [Hash]
      #
      # @return [void]
      #
      # @note Modifies `form_data`
      #
      def expand(form_data)
        expand_dependent_status(form_data)
        # TO-DO: Refactor custodian expansion
        expand_custodians(form_data)
      end

      private

      ##
      # Expands dependent status and household counts within form data
      #
      # @param form_data [Hash] The form data to be expanded
      #
      # @return [Hash] The updated form data hash
      #
      def expand_dependent_status(form_data)
        form_data.merge!(
          {
            'dependentChildrenInHousehold' => select_children_in_household(form_data['dependents']),
            'dependents' => expand_dependents(form_data['dependents'])
          }
        )
      end

      ##
      # Select the children in a household of the dependents
      #
      # @param dependents [Array<Hash>]
      #
      # @return [Integer] Number of children in household
      #
      def select_children_in_household(dependents)
        return if dependents.blank?

        dependents.select { |dependent| dependent['childInHousehold'] }.length
      end

      ##
      # Expands an array of dependent hashes with formatted details
      #
      # @param dependents [Array<Hash>, nil] The list of dependent records
      #
      # @return [Array<Hash>, nil] The expanded list of dependent records
      #
      def expand_dependents(dependents)
        return if dependents.blank?

        dependents.map do |dependent|
          dependent.merge!(
            {
              'fullName' => expand_full_name(dependent['fullName']),
              'childDateOfBirth' => split_date(dependent['childDateOfBirth']),
              'childDateOfBirthOverflow' => to_date_string(dependent['childDateOfBirth']),
              'childSocialSecurityNumber' => split_ssn(dependent['childSocialSecurityNumber']),
              'childSocialSecurityNumberOverflow' => dependent['childSocialSecurityNumber'],
              'childRelationship' => expand_child_relationship(dependent['childRelationship']),
              'disabled' => to_checkbox_on_off_v2(dependent['disabled']),
              'attendingCollege' => to_checkbox_on_off_v2(dependent['attendingCollege']),
              'previouslyMarried' => to_checkbox_on_off_v2(dependent['previouslyMarried']),
              'childNotInHousehold' => to_checkbox_on_off_v2(!dependent['childInHousehold']),
              'childStatusOverflow' => child_status_overflow(dependent).join(', '),
              'monthlyPayment' => expand_currency(dependent['monthlyPayment']),
              'personWhoLivesWithChild' => expand_full_name(dependent['personWhoLivesWithChild'])
            }
          )
        end
      end

      ##
      # Expands child relationship types into checkbox configurations
      #
      # @param relationship [String] The relationship type string
      #
      # @return [Hash] Hash containing checkbox state values
      #
      def expand_child_relationship(relationship)
        {
          'biological' => to_checkbox_on_off_v2(relationship == 'BIOLOGICAL'),
          'adopted' => to_checkbox_on_off_v2(relationship == 'ADOPTED'),
          'stepchild' => to_checkbox_on_off_v2(relationship == 'STEP_CHILD')
        }
      end

      ##
      # Expands custodian details and groups dependents living outside the household
      #
      # @param form_data [Hash] The form data containing dependent records
      #
      # @return [void]
      #
      def expand_custodians(form_data)
        custodian_addresses = {}
        dependents_not_in_household = form_data['dependents']&.reject { |dep| dep['childInHousehold'] } || []
        dependents_not_in_household.each do |dependent|
          custodian_key = dependent['personWhoLivesWithChild'].values.join('_')
          if custodian_addresses[custodian_key].nil?
            custodian_addresses[custodian_key] = build_custodian_hash_from_dependent(dependent)
          else
            custodian_addresses[custodian_key]['dependentsWithCustodianOverflow'] +=
              ", #{dependent['fullName']&.values&.join(' ')}"
          end
        end
        if custodian_addresses.any?
          form_data['dependentsNotWithYouAtSameAddress'] = to_radio_yes_no(custodian_addresses.length == 1)
        end
        form_data['custodians'] = custodian_addresses.values
      end

      ##
      # Build the custodian data from dependents
      #
      # @param dependent [Hash] The dependent record containing custodian information
      #
      # @return [Hash] The built custodian hash
      #
      def build_custodian_hash_from_dependent(dependent)
        dependent = dependent['personWhoLivesWithChild']
                    .merge({
                             'custodianAddress' => dependent['childAddress'].merge(
                               'postalCode' => split_postal_code(dependent['childAddress'])
                             )
                           })
                    .merge({
                             'custodianAddressOverflow' => build_address_string(dependent['childAddress']),
                             'dependentsWithCustodianOverflow' => dependent['fullName']&.values&.join(' ')
                           })
        dependent['custodianAddress']['country'] =
          dependent.dig('custodianAddress', 'country')&.slice(0, 2)
        dependent
      end

      ##
      # Create an address string from an address hash
      #
      # @param address [Hash]
      #
      # @return [String]
      #
      # @note Returns empty string if address is blank
      #
      def build_address_string(address)
        return '' if address.blank?

        country = address['country'].present? ? "#{address['country']}, " : ''
        address_arr = [
          address['street'].to_s, address['street2'].presence,
          "#{address['city']}, #{address['state']}, #{country}#{address['postalCode']}"
        ].compact

        address_arr.join("\n")
      end

      ##
      # Build a string to represent the dependents status.
      #
      # @param dependent [Hash]
      #
      # @return [Array<String>] Array of status strings
      #
      def child_status_overflow(dependent)
        child_status_overflow = [dependent['childRelationship']&.humanize]
        child_status_overflow << 'seriously disabled' if dependent['disabled']
        child_status_overflow << '18-23 years old (in school)' if dependent['attendingCollege']
        child_status_overflow << 'previously married' if dependent['previouslyMarried']
        child_status_overflow << 'does not live with you but contributes' unless dependent['childInHousehold']
        child_status_overflow
      end
    end
  end
end
