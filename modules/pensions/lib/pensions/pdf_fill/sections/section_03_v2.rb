# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section III: Veteran Service Information
    class Section3V2 < Section
      # Character limit for placeOfSeparation string
      SEPARATION_LIMIT = 36
      # Line character limit for placeOfSeparation string
      SEPARATION_LIMIT_PER_LINE = 18

      # Section configuration hash
      KEY = {
        # 3a
        'previousNames' => {
          item_label: 'Other service name',
          limit: 1,
          first_key: 'first',
          'first' => {
            limit: 12,
            question_num: 3,
            question_suffix: 'A',
            question_label: 'Other First Name',
            question_text: 'OTHER FIRST NAME',
            key: "previous_name_first[#{ITERATOR}]"
          },
          'last' => {
            limit: 18,
            question_num: 3,
            question_suffix: 'A',
            question_label: 'Other Last Name',
            question_text: 'OTHER LAST NAME',
            key: "previous_name_last[#{ITERATOR}]"
          }
        },
        # 3b
        'activeServiceDateRange' => {
          'from' => {
            'month' => {
              key: 'active_duty_month'
            },
            'day' => {
              key: 'active_duty_day'
            },
            'year' => {
              key: 'active_duty_year'
            }
          },
          'to' => {
            'month' => {
              key: 'release_month'
            },
            'day' => {
              key: 'release_day'
            },
            'year' => {
              key: 'release_year'
            }
          }
        },
        # 3d
        'serviceNumber' => {
          key: 'service_number'
        },
        # 3e
        'serviceBranch' => {
          'army' => {
            key: 'army'
          },
          'navy' => {
            key: 'navy'
          },
          'airForce' => {
            key: 'air_force'
          },
          'coastGuard' => {
            key: 'coast_guard'
          },
          'marineCorps' => {
            key: 'marine_corps'
          },
          'spaceForce' => {
            key: 'space_force'
          },
          'usphs' => {
            key: 'usphs'
          },
          'noaa' => {
            key: 'noaa'
          }
        },
        # 3f
        'placeOfSeparationLineOne' => {
          limit: SEPARATION_LIMIT,
          question_num: 3,
          question_suffix: 'F',
          question_label: 'Place of Your Last Separation',
          question_text: 'PLACE OF YOUR LAST SEPARATION',
          key: 'place_of_last_separation_1'
        },
        'placeOfSeparationLineTwo' => {
          key: 'place_of_last_separation_2'
        },
        'pow' => {
          key: 'pow'
        },
        # 3h
        'powDateRange' => {
          'from' => {
            'month' => {
              key: 'pow_start_month'
            },
            'day' => {
              key: 'pow_start_day'
            },
            'year' => {
              key: 'pow_start_year'
            }
          },
          'to' => {
            'month' => {
              key: 'pow_end_month'
            },
            'day' => {
              key: 'pow_end_day'
            },
            'year' => {
              key: 'pow_end_year'
            }
          }
        }
      }.freeze

      ##
      # Expand the form data for Veteran service history.
      #
      # @param form_data [Hash] The form data hash.
      #
      # @return [Hash, nil] form data or nil
      #
      # Note: This method modifies `form_data`
      #
      def expand(form_data)
        form_data.merge!(
          {
            'previousNames' => form_data['previousNames']&.map { |name| name['previousFullName'] },
            'activeServiceDateRange' => {
              'from' => split_date(form_data.dig('activeServiceDateRange', 'from')),
              'to' => split_date(form_data.dig('activeServiceDateRange', 'to'))
            },
            'serviceBranch' => expand_service_branch(form_data['serviceBranch']),
            'pow' => to_radio_yes_no(form_data['powDateRange'].present?)

          }
        )
        expand_place_of_separation(form_data)
        # Skip 3H if NO to POW
        expand_pow_date_range(form_data) if yes?(form_data['pow'])
      end

      private

      ##
      # Expand service branch information.
      #
      # @param service_branch [Hash]
      #
      # @return [Hash]
      #
      # Note: This method modifies `form_data`
      #
      def expand_service_branch(service_branch)
        return if service_branch.blank?

        service_branch.transform_values! { |served| to_checkbox_on_off_v2(served) }
      end

      ##
      # Handle overflow if place of separation exceeds two lines
      #
      # @params form_data [Hash]
      #
      # @return [Hash, String, nil]
      #
      # Note: This method modifies `form_data`
      #
      def expand_place_of_separation(form_data)
        return if form_data['placeOfSeparation'].blank?

        place = form_data['placeOfSeparation']
        if place.length <= SEPARATION_LIMIT
          pointer = SEPARATION_LIMIT_PER_LINE
          form_data.merge!(
            {
              'placeOfSeparationLineOne' => place[0..(pointer - 1)],
              'placeOfSeparationLineTwo' => place[pointer..]
            }
          )
        else
          # overflow
          form_data['placeOfSeparationLineOne'] = form_data.delete('placeOfSeparation')
        end
      end

      ##
      # Expand POW date range
      #
      # @params form_data [Hash]
      #
      # @return [Hash]
      #
      # Note: This method modifies `form_data`
      #
      def expand_pow_date_range(form_data)
        form_data['powDateRange'] = {
          'to' => split_date(form_data.dig('powDateRange', 'to')),
          'from' => split_date(form_data.dig('powDateRange', 'from'))
        }
      end
    end
  end
end
