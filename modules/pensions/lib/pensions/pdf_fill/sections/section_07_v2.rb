# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section VII: Prior Marital History
    class Section7V2 < Section
      # Section configuration hash
      KEY = {
        # 7a-m Veteran's prior marriages
        'marriages' => {
          limit: 2,
          first_key: 'otherExplanation',
          item_label: 'Veteran\'s prior marriage',
          question_num: 7,
          # 7a
          'spouseFullName' => {
            'first' => {
              limit: 12,
              question_num: 7,
              question_suffix: 'A',
              key: "previous_spouse_first_name[#{ITERATOR}]"
            },
            'middle' => {
              question_num: 7,
              question_suffix: 'A',
              key: "previous_spouse_middle_name[#{ITERATOR}]"
            },
            'last' => {
              limit: 18,
              question_num: 7,
              question_suffix: 'A',
              key: "previous_spouse_last_name[#{ITERATOR}]"
            }
          },
          # 7a overflow
          'spouseFullNameOverflow' => {
            question_num: 7,
            question_label: "Previous Spouse's Full Name",
            question_text: 'PREVIOU SPOUSE\'S FULL NAME'
          },
          # 7b
          'reasonForSeparation' => {
            key: "reason_for_marriage_end[#{ITERATOR}]"
          },
          'reasonForSeparationOverflow' => {
            question_num: 7,
            question_suffix: 'A',
            question_label: 'How Did Your Previous Marriage End?',
            question_text: 'HOW DID YOUR PREVIOUS MARRIAGE END?'
          },
          'otherExplanation' => {
            limit: 66,
            question_num: 7,
            question_suffix: 'A',
            question_label: 'How Did Your Previous Marriage End (Other Reason)?',
            question_text: 'HOW DID YOUR PREVIOUS MARRIAGE END (OTHER REASON)?',
            key: "marriage_end_reason_other[#{ITERATOR}]"
          },
          # 7c
          'dateOfMarriage' => {
            'month' => {
              key: "prior_marriage_start_month[#{ITERATOR}]"
            },
            'day' => {
              key: "prior_marriage_start_day[#{ITERATOR}]"
            },
            'year' => {
              key: "prior_marriage_start_year[#{ITERATOR}]"
            }
          },
          # 7d
          'dateOfSeparation' => {
            'month' => {
              key: "prior_marriage_end_month[#{ITERATOR}]"
            },
            'day' => {
              key: "prior_marriage_end_day[#{ITERATOR}]"
            },
            'year' => {
              key: "prior_marriage_end_year[#{ITERATOR}]"
            }
          },
          'dateRangeOfMarriageOverflow' => {
            question_num: 7,
            question_suffix: 'A',
            question_label: 'What Are The Dates Of The Previous Marriage?',
            question_text: 'WHAT ARE THE DATES OF THE PREVIOUS MARRIAGE?'
          },
          # 7e
          'locationOfMarriage' => {
            limit: 49,
            question_num: 7,
            question_suffix: 'A',
            question_label: 'Place Of Marriage',
            question_text: 'PLACE OF MARRIAGE',
            key: "prior_marriage_location[#{ITERATOR}]"
          },
          # 7f
          'locationOfSeparation' => {
            limit: 43,
            question_num: 7,
            question_suffix: 'A',
            question_label: 'Place Marriage Ended',
            question_text: 'PLACE MARRIAGE ENDED',
            key: "prior_separation_location[#{ITERATOR}]"
          }
        },
        # 7m
        'additionalMarriages' => {
          key: 'additional_marriages'
        },
        # 7n-y Spouse's prior marriages
        'spouseMarriages' => {
          limit: 2,
          item_label: 'Current spouse\'s prior marriage',
          first_key: 'otherExplanation',
          # 7n
          'spouseFullName' => {
            'first' => {
              limit: 12,
              question_num: 7,
              question_suffix: 'B',
              key: "spouses_previous_spouse_first_name[#{ITERATOR}]"
            },
            'middle' => {
              question_num: 7,
              question_suffix: 'B',
              key: "spouses_previous_spouse_middle_name[#{ITERATOR}]"
            },
            'last' => {
              limit: 18,
              question_num: 7,
              question_suffix: 'B',
              key: "spouses_previous_spouse_last_name[#{ITERATOR}]"
            }
          },
          # 7n overflow
          'spouseFullNameOverflow' => {
            question_num: 7,
            question_suffix: 'B',
            question_label: "Previous Spouse's Full Name",
            question_text: 'PREVIOU SPOUSE\'S FULL NAME'
          },
          # 7o
          'reasonForSeparation' => {
            key: "spouse_reason_for_marriage_end[#{ITERATOR}]"
          },
          'reasonForSeparationOverflow' => {
            question_num: 7,
            question_suffix: 'B',
            question_label: 'How Did The Previous Marriage End?',
            question_text: 'HOW DID THE PREVIOUS MARRIAGE END?'
          },
          'otherExplanation' => {
            limit: 66,
            question_num: 7,
            question_suffix: 'B',
            question_label: 'How Did The Previous Marriage End (Other Reason)?',
            question_text: 'HOW DID THE PREVIOUS MARRIAGE END (OTHER REASON)?',
            key: "spouse_marriage_end_reason_other[#{ITERATOR}]"
          },
          # 7p
          'dateOfMarriage' => {
            'month' => {
              key: "spouse_prior_marriage_start_month[#{ITERATOR}]"
            },
            'day' => {
              key: "spouse_prior_marriage_start_day[#{ITERATOR}]"
            },
            'year' => {
              key: "spouse_prior_marriage_start_year[#{ITERATOR}]"
            }
          },
          # 7q
          'dateOfSeparation' => {
            'month' => {
              key: "spouse_prior_marriage_end_month[#{ITERATOR}]"
            },
            'day' => {
              key: "spouse_prior_marriage_end_day[#{ITERATOR}]"
            },
            'year' => {
              key: "spouse_prior_marriage_end_year[#{ITERATOR}]"
            }
          },
          'dateRangeOfMarriageOverflow' => {
            question_num: 7,
            question_suffix: 'B',
            question_label: 'What Are The Dates Of The Previous Marriage?',
            question_text: 'WHAT ARE THE DATES OF THE PREVIOUS MARRIAGE?'
          },
          # 7r
          'locationOfMarriage' => {
            limit: 49,
            question_num: 7,
            question_suffix: 'B',
            question_label: 'Place Of Marriage',
            question_text: 'PLACE OF MARRIAGE',
            key: "spouse_prior_marriage_location[#{ITERATOR}]"
          },
          # 7s
          'locationOfSeparation' => {
            limit: 43,
            question_num: 7,
            question_suffix: 'B',
            question_label: 'Place Marriage Ended',
            question_text: 'PLACE MARRIAGE ENDED',
            key: "spouse_prior_separation_location[#{ITERATOR}]"
          }
        },
        # 7z
        'additionalSpouseMarriages' => {
          key: 'additional_spouse_marriages'
        }
      }.freeze

      ##
      # Expand the form data for prior marital history.
      #
      # @param form_data [Hash] The form data hash.
      #
      # @return [void]
      #
      # Note: This method modifies `form_data`
      #
      def expand(form_data)
        expand_prior_marital_history(form_data)
      end

      private

      ##
      # Expand prior marital history data.
      #
      # @param form_data [Hash] The form data hash.
      #
      # @return [void]
      #
      #  Note: This method modifies `form_data`
      #
      def expand_prior_marital_history(form_data)
        build_marital_history(form_data['marriages'])
        build_marital_history(form_data['spouseMarriages'])
        if form_data['marriages']&.any?
          form_data['additionalMarriages'] = to_radio_yes_no(form_data['marriages'].length > 2)
        end
        if form_data['spouseMarriages']&.any?
          form_data['additionalSpouseMarriages'] = to_radio_yes_no(form_data['spouseMarriages'].length > 2)
        end
      end

      ##
      # Build marital history entries.
      #
      # @param marriages [Array<Hash>] The array of marriage entries.
      #
      # @return [Array<Hash>, nil] The processed array of marriage entries, or nil if blank.
      #
      # @note This method modifies `marriages` in-place.
      #
      def build_marital_history(marriages)
        return if marriages.blank?

        marriages.each do |marriage|
          marriage.merge!(
            {
              'spouseFullName' => extract_middle_initial(marriage['spouseFullName']),
              'dateOfMarriage' => split_date(marriage['dateOfMarriage']),
              'dateOfSeparation' => split_date(marriage['dateOfSeparation']),
              'dateRangeOfMarriageOverflow' => build_date_range_string({
                                                                         'from' => marriage['dateOfMarriage'],
                                                                         'to' => marriage['dateOfSeparation']
                                                                       }),
              'reasonForSeparation' => REASON_FOR_MARRIAGE_END.fetch(marriage['reasonForSeparation'], 'Off'),
              'reasonForSeparationOverflow' => marriage['reasonForSeparation']&.humanize
            }
          )
          marriage['spouseFullNameOverflow'] = marriage['spouseFullName'].values.compact.join(' ')
        end
      end
    end
  end
end
