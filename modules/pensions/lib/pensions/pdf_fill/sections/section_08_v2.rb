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
              key: "child_first_name[#{ITERATOR}]"
            },
            'middle' => {
              question_num: 8,
              key: "child_middle_name[#{ITERATOR}]"
            },
            'last' => {
              limit: 18,
              question_num: 8,
              key: "child_last_name[#{ITERATOR}]"
            }
          },
          # 8b overflow
          'fullNameOverflow' => {
            question_num: 8,
            question_label: "Child's Full Name",
            question_text: 'CHILD\'S FULL NAME'
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
          # 8f
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
            question_label: 'Annual Contribution To Child',
            question_text: 'ANNUAL CONTRIBUTUION TO CHILD',
            key: "child_monthly_payment[#{ITERATOR}]",
            dollar: true
          },
          # 8r overflow
          'personWhoLivesWithChild' => {
            question_num: 8,
            question_label: "Custodian's Full Name",
            question_text: 'CUSTODIAN\'S FULL NAME'
          },
          # 8s overflow
          'custodianAddressOverflow' => {
            question_num: 8,
            question_label: "Custodian's Address",
            question_text: 'CUSTODIAN\'S ADDRESS'
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
            question_num: 8
          },
          'middle' => {
            key: "custodian_middle_name[#{ITERATOR}]"
          },
          'last' => {
            limit: 18,
            key: "custodian_last_name[#{ITERATOR}]",
            question_num: 8
          },
          # 8s
          'custodianAddress' => {
            'street' => {
              limit: 30,
              question_num: 8,
              key: "custodian_street_1[#{ITERATOR}]"
            },
            'street2' => {
              limit: 5,
              question_num: 8,
              key: "custodian_street_2[#{ITERATOR}]"
            },
            'city' => {
              limit: 18,
              question_num: 8,
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
                key: "custodian_postal_code_2[#{ITERATOR}]",
                limit: 4,
                question_num: 8
              }
            }
          }
        }
      }.freeze

      ##
      # Expand dependent children section
      #
      # @param form_data [Hash]
      #
      # @return [void]
      #
      # @note Modifies `form_data`
      #
      def expand(form_data)
        expand_dependents(form_data)
      end

      private

      ##
      # Expand an array of dependent hashes with formatted details
      #
      # @param form_data [Hash]
      #
      # @note Modifies `form_data`
      #
      def expand_dependents(form_data)
        return if form_data['dependents'].blank?

        form_data['dependentChildrenInHousehold'] = 0
        form_data['custodians'] = []
        @custodian_names = []

        form_data['dependents'].each do |dependent|
          form_data['dependentChildrenInHousehold'] += 1 if dependent['childInHousehold']
          build_dependent(dependent)
          expand_custodian(dependent, form_data['custodians'])
        end
        only_one_custodian = @custodian_names.size == 1
        form_data['dependentsNotWithYouAtSameAddress'] = to_radio_yes_no(only_one_custodian)
      end

      ##
      # Expand dependent attributes
      #
      # @param dependent [Hash]
      #
      # @note Modifies `form_data`
      #
      def build_dependent(dependent)
        dependent.merge!(
          {
            'fullName' => extract_middle_initial(dependent['fullName']),
            'childDateOfBirth' => split_date(dependent['childDateOfBirth']),
            'childDateOfBirthOverflow' => to_date_string(dependent['childDateOfBirth']),
            'childSocialSecurityNumber' => split_ssn(dependent['childSocialSecurityNumber']),
            'childSocialSecurityNumberOverflow' => dependent['childSocialSecurityNumber'],
            'childRelationship' => expand_child_relationship(dependent['childRelationship']),
            'disabled' => to_checkbox_on_off(dependent['disabled']),
            'attendingCollege' => to_checkbox_on_off(dependent['attendingCollege']),
            'previouslyMarried' => to_checkbox_on_off(dependent['previouslyMarried']),
            'childNotInHousehold' => to_checkbox_on_off(!dependent['childInHousehold']), # NOTE: negation
            'childStatusOverflow' => child_status_overflow(dependent)
          }
        )
        dependent['fullNameOverflow'] = dependent['fullName'].values.compact.join(' ')
        expand_dependent_not_in_house(dependent) if yes?(dependent['childNotInHousehold'])
      end

      ##
      # Expand child relationship types into checkbox configurations
      #
      # @param relationship [String] The relationship type string
      #
      # @return [Hash] Hash containing checkbox state values
      #
      def expand_child_relationship(relationship)
        {
          'biological' => to_checkbox_on_off(relationship == 'BIOLOGICAL'),
          'adopted' => to_checkbox_on_off(relationship == 'ADOPTED'),
          'stepchild' => to_checkbox_on_off(relationship == 'STEP_CHILD')
        }
      end

      ##
      # Build a string to represent the dependents status.
      #
      # @param dependent [Hash]
      #
      # @return [String]
      #
      def child_status_overflow(dependent)
        child_status_overflow = [dependent['childRelationship']&.humanize]
        child_status_overflow << 'seriously disabled' if dependent['disabled']
        child_status_overflow << '18-23 years old (in school)' if dependent['attendingCollege']
        child_status_overflow << 'previously married' if dependent['previouslyMarried']
        child_status_overflow << 'does not live with you but contributes' unless dependent['childInHousehold']
        child_status_overflow.join(', ')
      end

      ##
      # Expand attributes of dependent living outside of household
      #
      # @param dependent [Hash]
      #
      # @note Modifies `form_data`
      #
      def expand_dependent_not_in_house(dependent)
        dependent['monthlyPayment'] = expand_currency(dependent['monthlyPayment'])
        address = dependent['childAddress']
        return if address.blank?

        address['postalCode'] = split_postal_code(address)
        dependent['custodianAddressOverflow'] = address_block(
          address.merge('postalCode' => address['postalCode'].values.compact_blank.join('-'))
        )
      end

      ##
      # Expand custodian attributes
      #
      # @param dependent [Hash]
      # @param custodians [Set<Hash>]
      #
      # @note Modifies `form_data`
      #
      def expand_custodian(dependent, custodians)
        # NOTE: dependent['childInHousehold'] is boolean, never converted to radio on/off
        return if dependent['personWhoLivesWithChild'].blank? && dependent['childInHousehold']

        # TODO: A user currently has to re-enter custodian name even if the same, and could technically
        # enter name slightly different even though the same custodian. Solution could be to allow user
        # to choose from previously entered custodian instead of re-typing fields
        name_key = dependent['personWhoLivesWithChild'].values.compact.join('_')
        unless name_key.in?(@custodian_names)
          custodian = dependent['personWhoLivesWithChild'].merge('custodianAddress' => dependent['childAddress'])
          custodians << custodian
          @custodian_names << name_key
        end

        dependent['personWhoLivesWithChild'] =
          extract_middle_initial(dependent['personWhoLivesWithChild']).values.compact.join(' ')
      end
    end
  end
end
