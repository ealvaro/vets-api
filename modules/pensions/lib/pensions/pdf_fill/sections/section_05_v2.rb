# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section V: Employment History
    class Section5V2 < Section
      # Section configuration hash
      KEY = {
        # 5a
        'currentEmployment' => {
          key: 'current_employment'
        },
        'currentEmployers' => {
          item_label: 'Current job',
          limit: 1,
          first_key: 'jobType',
          # 5b
          'jobType' => {
            limit: 35,
            question_num: 5,
            question_suffix: 'B',
            question_label: 'What Kind Of Work Are You Currently Doing',
            question_text: 'WHAT KIND OF WORK ARE YOU CURRENTLY DOING',
            key: 'current_job_type'
          },
          # 5c
          'jobHoursWeek' => {
            limit: 3,
            question_num: 5,
            question_suffix: 'C',
            question_label: 'How Many Hours Per Week Do You Average',
            question_text: 'HOW MANY HOURS PER WEEK DO YOU AVERAGE',
            key: 'current_job_hours_week'
          }
        },
        'previousEmployers' => {
          item_label: 'Previous job',
          limit: 1,
          first_key: 'jobTitle',
          # 5d
          'jobDate' => {
            'month' => {
              key: 'previous_job_month'
            },
            'day' => {
              key: 'previous_job_day'
            },
            'year' => {
              key: 'previous_job_year'
            }
          },
          'jobDateOverflow' => {
            question_num: 5,
            question_suffix: 'D',
            question_label: 'When Did You Last Work',
            question_text: 'WHEN DID YOU LAST WORK'
          },
          # 5e
          'jobHoursWeek' => {
            limit: 3,
            question_num: 5,
            question_suffix: 'E',
            question_label: 'How Many Hours Per Week Did You Average',
            question_text: 'HOW MANY HOURS PER WEEK DID YOU AVERAGE',
            key: 'previous_job_hours_week'
          },
          # 5f
          'jobTitle' => {
            limit: 30,
            question_num: 5,
            question_suffix: 'F',
            question_label: 'What Was Your Job Title',
            question_text: 'WHAT WAS YOUR JOB TITLE',
            key: 'previous_job_title'
          },
          # 5g
          'jobType' => {
            limit: 27,
            question_num: 5,
            question_suffix: 'G',
            question_label: 'What Kind Of Work Did You Do',
            question_text: 'WHAT KIND OF WORK DID YOU DO',
            key: 'previous_job_type'
          }
        }
      }.freeze

      ##
      # Expand the form data for employment history.
      #
      # @param form_data [Hash] The form data hash.
      #
      # @return [void]
      #
      # Note: This method modifies `form_data`
      #
      def expand(form_data)
        form_data['currentEmployment'] = to_radio_yes_no(form_data['currentEmployment'])
        # If not currently employed, skip 5B and 5C
        form_data.delete('currentEmployers') unless yes?(form_data['currentEmployment'])
        form_data['previousEmployers'] = expand_previous_employers(form_data['previousEmployers'])
      end

      private

      ##
      # Expands the collection of previous employers by formatting date structures
      # and generating corresponding date overflow strings for PDF filling.
      #
      # @param employers [Array<Hash>, nil] A collection of previous employer hashes.
      #
      # @return [Array<Hash>, nil] The processed collection of previous employer hashes,
      #   or `nil` if the input is blank.
      #
      def expand_previous_employers(employers)
        return if employers.blank?

        employers.map do |employer|
          employer.merge(
            {
              'jobDate' => split_date(employer['jobDate']),
              'jobDateOverflow' => to_date_string(employer['jobDate'])
            }
          )
        end
      end
    end
  end
end
