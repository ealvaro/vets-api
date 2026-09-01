# frozen_string_literal: true

module PdfFill
  module Forms
    class Va2210272 < FormBase
      include FormHelper

      BENEFIT_PROGRAMS = %w[chapter33 chapter35].freeze

      # rubocop:disable Layout/LineLength
      KEY = {
        'vaBenefitProgram' => {
          key: 'vaBenefitProgram',
          question_text: 'Select the education benefit under which you are requesting Prep Course fee reimbursement',
          question_num: 0,
          'chapter33' => {
            key: 'chapter33',
            question_text: 'Post-9/11 GI Bill Including Transfer of Entitlement and Fry Scholarship Recipients (Chapter 33)'
          },
          'chapter35' => {
            key: 'chapter35',
            question_text: 'Survivors\' and Dependents\' Educational Assistance Program (DEA) (Chapter 35)'
          }
        },
        'applicantName' => {
          key: 'applicantName',
          question_text: 'APPLICANT\'S NAME (First, Middle Initial, Last Name)',
          question_num: 1,
          limit: 118
        },
        'mailingAddress' => {
          key: 'mailingAddress',
          question_text: 'MAILING ADDRESS (Complete Street Address, City, State and 9-Digit ZIP Code)',
          question_num: 2,
          limit: 280,
          multiline_limit: 4
        },
        'emailAddress' => {
          key: 'emailAddress',
          question_text: 'APPLICANT\'S EMAIL ADDRESS',
          question_num: 3,
          limit: 54
        },
        'mobilePhone' => {
          key: 'mobilePhone',
          question_text: 'MOBILE',
          question_num: 4,
          question_suffix: 'A',
          limit: 26
        },
        'homePhone' => {
          key: 'homePhone',
          question_text: 'HOME',
          question_num: 4,
          question_suffix: 'B',
          limit: 34
        },
        'vaFileNumber' => {
          key: 'vaFileNumber',
          question_text: 'VA FILE NUMBER (For chapter 35, enter the Veteran\'s file number and your Payee Number)',
          question_num: 5,
          limit: 70
        },
        'hasPreviouslyApplied' => {
          question_text: 'HAVE YOU PREVIOUSLY APPLIED FOR VA EDUCATION BENEFITS? (Please check the appropriate box below:)',
          question_num: 6,
          'yes' => {
            key: 'hasPreviouslyAppliedYes',
            question_text: 'YES'
          },
          'no' => {
            key: 'hasPreviouslyAppliedNo',
            question_text: 'NO'
          }
        },
        'testName' => {
          key: 'testName',
          question_text: 'NAME OF TEST FOR WHICH THE PREP COURSE WILL PREPARE YOU',
          question_num: 7,
          limit: 70
        },
        'orgNameAndAddress' => {
          key: 'orgNameAndAddress',
          question_text: 'NAME AND ADDRESS OF ORGANIZATION AWARDING LICENSE OR CERTIFICATION',
          question_num: 8,
          limit: 280,
          multiline_limit: 4
        },
        'prepCourseName' => {
          key: 'prepCourseName',
          question_text: 'NAME OF PREP COURSE',
          question_num: 9,
          limit: 76,
          multiline_limit: 2
        },
        'prepCourseOrgNameAndAddress' => {
          key: 'prepCourseOrgNameAndAddress',
          question_text: 'NAME AND ADDRESS OF ORGANIZATION GIVING PREP COURSE',
          question_num: 10,
          limit: 448,
          multiline_limit: 14
        },
        'prepCourseCost' => {
          key: 'prepCourseCost',
          question_text: 'TOTAL PREP COURSE COST INCLUDING MANDATORY FEES (You must attach a receipt)',
          question_num: 11,
          limit: 38
        },
        'prepCourseTakenOnline' => {
          question_text: 'TAKEN ONLINE?',
          question_num: 12,
          question_suffix: 'A',
          'yes' => {
            key: 'prepCourseTakenOnlineYes',
            question_text: 'YES'
          },
          'no' => {
            key: 'prepCourseTakenOnlineNo',
            question_text: 'NO'
          }
        },
        'prepCourseStartDate' => {
          key: 'prepCourseStartDate',
          question_text: 'COURSE START DATE (MM/DD/YYYY)',
          question_num: 12,
          question_suffix: 'B',
          limit: 19
        },
        'prepCourseEndDate' => {
          key: 'prepCourseEndDate',
          question_text: 'COURSE END DATE (MM/DD/YYYY)',
          question_num: 12,
          question_suffix: 'C',
          limit: 19
        },
        'remarks' => {
          key: 'remarks',
          question_text: 'REMARKS',
          question_num: 14,
          limit: 2590,
          multiline_limit: 37
        },
        'statementOfTruthSignature' => {
          key: 'statementOfTruthSignature',
          question_text: 'SIGNATURE OF APPLICANT',
          question_num: 15,
          limit: 52
        },
        'dateSigned' => {
          key: 'dateSigned',
          question_text: 'DATE SIGNED (MM/DD/YYYY)',
          question_num: 16,
          limit: 16
        }
      }.freeze
      # rubocop:enable Layout/LineLength

      def merge_fields(_options = {})
        merge_identification_helpers
        merge_education_helpers
        merge_licensing_helpers
        merge_prep_course_helpers
        merge_date_helpers

        @form_data
      end

      private

      def merge_identification_helpers
        format_applicant_name(@form_data['applicantName'])
        format_address(@form_data['mailingAddress'])
        format_va_file_number
      end

      def format_applicant_name(name)
        # Convert middle name to middle initial if present
        name['middle'] = "#{name['middle'][0]}." if name['middle']
        @form_data['applicantName'] = combine_full_name(name)
      end

      def format_address(address)
        @country = address['country']
        normalize_mailing_address(address)
        @form_data['mailingAddress'] = combine_full_address_extras(address)
      end

      def format_va_file_number
        append_payee_number = @form_data['vaFileNumber'].present? && @form_data['vaBenefitProgram'] == 'chapter35'
        @form_data['vaFileNumber'] = if append_payee_number
                                       "#{format_ssn(@form_data['vaFileNumber'])} #{@form_data['payeeNumber']}"
                                     else
                                       format_ssn(@form_data['ssn'] || @form_data['vaFileNumber'])
                                     end
      end

      def merge_education_helpers
        format_yes_no_checkbox('hasPreviouslyApplied')
        format_benefit_program_checkbox
      end

      def merge_licensing_helpers
        normalize_mailing_address(@form_data['organizationAddress'])
        @form_data['orgNameAndAddress'] = combine_name_addr_extras(@form_data,
                                                                   'organizationName',
                                                                   'organizationAddress')
      end

      def merge_prep_course_helpers
        normalize_mailing_address(@form_data['prepCourseOrganizationAddress'])
        @form_data['prepCourseOrgNameAndAddress'] = combine_name_addr_extras(@form_data,
                                                                             'prepCourseOrganizationName',
                                                                             'prepCourseOrganizationAddress')
        format_yes_no_checkbox('prepCourseTakenOnline')
        @form_data['prepCourseCost'] = format_cost(@form_data['prepCourseCost'])
      end

      def format_yes_no_checkbox(boolean_key)
        flag = @form_data[boolean_key]
        @form_data[boolean_key] = {
          'yes' => flag ? 'Yes' : 'Off',
          'no' => flag ? 'Off' : 'Yes'
        }
      end

      def format_benefit_program_checkbox
        selected_program = @form_data.delete('vaBenefitProgram')
        @form_data['vaBenefitProgram'] = {}
        BENEFIT_PROGRAMS.each do |program|
          flag = program == selected_program
          @form_data['vaBenefitProgram'][program] = flag ? 'Yes' : 'Off'
        end
      end

      def format_cost(num)
        ActiveSupport::NumberHelper.number_to_currency(num)
      end

      def merge_date_helpers
        %w[prepCourseStartDate prepCourseEndDate dateSigned].each(&method(:format_date))
      end

      def format_date(key)
        str = @form_data[key]
        @form_data[key] = str.to_date.strftime(self.class.date_strftime)
      end

      def format_ssn(ssn)
        split_ssn(ssn).values.join('-')
      end
    end
  end
end
