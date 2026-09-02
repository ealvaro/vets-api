# frozen_string_literal: true

module PdfFill
  module Forms
    class Va220810 < FormBase
      include FormHelper

      BENEFIT_PROGRAMS = %w[chapter30 chapter33 chapter35 chapter1606].freeze

      # Template PDF is 3 pages; overflow pages start at page 4.
      START_PAGE = 4

      # question_number matches the real printed question number on the 22-0810 form.
      QUESTION_KEY = [
        { question_number: '1', question_text: "Applicant's Name" },
        { question_number: '2', question_text: "Applicant's Mailing Address" },
        { question_number: '3', question_text: "Applicant's Email Address" },
        { question_number: '7', question_text: 'Name of Exam' },
        { question_number: '8', question_text: 'Name and Address of Organization Giving Exam' },
        { question_number: '11', question_text: 'Remarks' },
        { question_number: '12', question_text: 'Signature of Applicant' }
      ].freeze

      # Groups overflow questions under the printed form's Part heading so the overflow
      # page renders a section header above each entry.
      SECTIONS = [
        {
          label: 'Part I - Identification Information',
          question_nums: %w[1 2 3]
        },
        {
          label: 'Part III - Exam Information',
          question_nums: %w[7 8 11]
        },
        {
          label: 'Part IV - Certification and Signature of Applicant',
          question_nums: %w[12]
        }
      ].freeze

      # rubocop:disable Layout/LineLength
      KEY = {
        'vaBenefitProgram' => {
          question_text: 'Select the education benefit under which you are requesting National Exam fee reimbursement',
          question_num: 0,
          'chapter30' => {
            key: 'chapter30',
            question_text: 'Montgomery GI Bill - Active Duty Educational Assistance Program (MGIB) (Chapter 30)'
          },
          'chapter33' => {
            key: 'chapter33',
            question_text: 'Post-9/11 GI Bill Including Transfer of Entitlement and Fry Scholarship Recipients (Chapter 33)'
          },
          'chapter35' => {
            key: 'chapter35',
            question_text: 'Survivors\' and Dependents\' Education Assistance Program (DEA) (Chapter 35)'
          },
          'chapter1606' => {
            key: 'chapter1606',
            question_text: 'Montgomery GI Bill - Selected Reserve Educational Assistance Program (MGIB-SR) (Chapter 1606)'
          }
        },
        'applicantName' => {
          key: 'applicantName',
          question_text: 'APPLICANT\'S NAME (First, Middle Initial, Last Name)',
          question_num: 1,
          limit: 107
        },
        'mailingAddress' => {
          key: 'mailingAddress',
          question_text: 'APPLICANT\'S ADDRESS (Number and street or rural route, P.O. Box, City, State, Zip Code)',
          question_num: 2,
          limit: 180,
          multiline_limit: 2
        },
        'emailAddress' => {
          key: 'emailAddress',
          question_text: 'APPLICANT\'S EMAIL ADDRESS',
          question_num: 3,
          limit: 107
        },
        'phone' => {
          question_text: 'TELEPHONE NUMBER (Include Area Code)',
          question_num: 4,
          'mobilePhone' => {
            key: 'mobilePhone',
            question_text: 'MOBILE',
            question_suffix: 'A',
            limit: 28
          },
          'homePhone' => {
            key: 'homePhone',
            question_text: 'HOME',
            question_suffix: 'B',
            limit: 29
          }
        },
        'vaFileNumber' => {
          key: 'vaFileNumber',
          question_text: 'VA FILE NUMBER (For chapter 35, enter the veteran\'s file number and include your suffix indicator. For Chapter 30 dependent\'s case, enter the file number of the person who transferred entitlement to you)',
          question_num: 5,
          limit: 107
        },
        'hasPreviouslyApplied' => {
          question_text: 'HAVE YOU PREVIOUSLY APPLIED FOR VA EDUCATION BENEFITS?',
          question_num: 6,
          'yes' => {
            key: 'hasPreviouslyAppliedYes',
            question_text: 'YES (If "Yes," show the specific benefit you previously applied for in Item 6B)'
          },
          'no' => {
            key: 'hasPreviouslyAppliedNo',
            question_text: 'NO (If "No," you must also complete an Application for VA Education Benefits, as indicated in "Important" paragraph instructions above)'
          }
        },
        'examName' => {
          key: 'examName',
          question_text: 'NAME OF EXAM (Use this form for one exam only)',
          question_num: 7,
          limit: 107
        },
        'organization' => {
          key: 'organization',
          question_text: 'NAME AND ADDRESS OF ORGANIZATION GIVING EXAM',
          question_num: 8,
          limit: 107,
          multiline_limit: 1
        },
        'examDate' => {
          key: 'examDate',
          question_text: 'DATE EXAM TAKEN (MM/DD/YYYY) (Attach a copy of exam results)',
          question_num: 9,
          limit: 107
        },
        'examCost' => {
          key: 'examCost',
          question_text: 'TOTAL COST OF EXAM INCLUDING MANDATORY FEES (Attach exam receipt)',
          question_num: 10,
          limit: 107
        },
        'remarks' => {
          key: 'remarks',
          question_text: 'REMARKS (Optional)',
          question_num: 11,
          limit: 456,
          multiline_limit: 5
        },
        'statementOfTruthSignature' => {
          key: 'statementOfTruthSignature',
          question_text: 'SIGNATURE OF APPLICANT',
          question_num: 12,
          limit: 78
        },
        'dateSigned' => {
          key: 'dateSigned',
          question_text: 'DATE SIGNED (MM/DD/YYYY)',
          question_num: 13,
          limit: 28
        }
      }.freeze
      # rubocop:enable Layout/LineLength

      def merge_fields(_options = {})
        merge_identification_helpers
        merge_benefit_program_helpers
        format_organization
        format_cost
        merge_date_helpers

        @form_data
      end

      private

      def merge_identification_helpers
        format_applicant_name(@form_data['applicantName'])
        format_address(@form_data['mailingAddress'])
        format_phone
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

      def format_phone
        @form_data['phone'] = @form_data.slice('homePhone', 'mobilePhone')
      end

      def format_va_file_number
        append_payee_number = @form_data['vaFileNumber'].present? && @form_data['vaBenefitProgram'] == 'chapter35'
        @form_data['vaFileNumber'] = if append_payee_number
                                       "#{format_ssn(@form_data['vaFileNumber'])} #{@form_data['payeeNumber']}"
                                     else
                                       format_ssn(@form_data['ssn'])
                                     end
      end

      def format_ssn(ssn)
        split_ssn(ssn).values.join('-')
      end

      def merge_benefit_program_helpers
        format_has_previously_applied_checkbox
        format_benefit_program_checkbox
      end

      def format_has_previously_applied_checkbox
        flag = @form_data['hasPreviouslyApplied']
        @form_data['hasPreviouslyApplied'] = {
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

      def format_organization
        normalize_mailing_address(@form_data['organizationAddress'])
        @form_data['organization'] = combine_name_addr_extras(@form_data,
                                                              'organizationName',
                                                              'organizationAddress')
      end

      def merge_date_helpers
        %w[examDate dateSigned].each(&method(:format_date))
      end

      def format_date(key)
        str = @form_data[key]
        @form_data[key] = str.to_date.strftime(self.class.date_strftime)
      end

      def format_cost
        @form_data['examCost'] = ActiveSupport::NumberHelper.number_to_currency(@form_data['examCost'])
      end
    end
  end
end
