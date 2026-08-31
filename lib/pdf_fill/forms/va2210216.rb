# frozen_string_literal: true

module PdfFill
  module Forms
    class Va2210216 < FormBase
      include FormHelper

      ITERATOR = PdfFill::HashConverter::ITERATOR

      # Template PDF is 2 pages; overflow pages start at page 3.
      START_PAGE = 3

      # Only the institution name is realistically long enough to overflow; other
      # fields are fixed-format (codes, dates, counts) or short (title, signature).
      QUESTION_KEY = [
        { question_number: '1', question_text: 'Institution Name' }
      ].freeze

      KEY = {
        'institutionDetails' => {
          'institutionName' => {
            key: 'Text1',
            limit: 50,
            question_num: 1,
            question_suffix: 'A',
            question_text: 'INSTITUTION NAME'
          },
          'facilityCode' => {
            key: 'Text2',
            limit: 8,
            question_num: 2,
            question_suffix: 'A',
            question_text: 'FACILITY CODE'
          },
          'termStartDate' => {
            key: 'Text3',
            limit: 14,
            question_num: 3,
            question_suffix: 'C',
            question_text: 'TERM START DATE'
          }
        },
        'studentRatioCalcChapter' => {
          'beneficiaryStudent' => {
            key: 'Text4',
            limit: 10,
            question_num: 4,
            question_suffix: 'A',
            question_text: 'NUMBER OF VA BENEFICIARY STUDENTS'
          },
          'numOfStudent' => {
            key: 'Text5',
            limit: 10,
            question_num: 5,
            question_suffix: 'A',
            question_text: 'TOTAL NUMBER OF STUDENTS'
          },
          'VABeneficiaryStudentsPercentage' => {
            key: 'Text6',
            limit: 10,
            question_num: 6,
            question_suffix: 'A',
            question_text: 'VA BENEFICIARY STUDENTS PERCENTAGE'
          },
          'dateOfCalculation' => {
            key: 'Text7',
            limit: 20,
            question_num: 7,
            question_suffix: 'C',
            question_text: 'DATE OF CALCULATION'
          }
        },
        'certifyingOfficial' => {
          'fullName' => {
            key: 'Text8',
            limit: 50,
            question_num: 8,
            question_suffix: 'A',
            question_text: 'CERTIFYING OFFICIAL NAME'
          },
          'title' => {
            key: 'Text9',
            limit: 30,
            question_num: 9,
            question_suffix: 'A',
            question_text: 'CERTIFYING OFFICIAL TITLE'
          }
        },
        'statementOfTruthSignature' => {
          key: 'Text10',
          limit: 50,
          question_num: 10,
          question_suffix: 'A',
          question_text: 'STATEMENT OF TRUTH SIGNATURE'
        },
        'dateSigned' => {
          key: 'Text11',
          limit: 10,
          question_num: 11,
          question_suffix: 'A',
          question_text: 'DATE SIGNED'
        }
      }.freeze

      def merge_fields(_options = {})
        form_data = @form_data

        # Combine first and last name into fullName
        if form_data['certifyingOfficial']
          official = form_data['certifyingOfficial']
          official['fullName'] = "#{official['first']} #{official['last']}" if official['first'] && official['last']
        end
        merge_date_helpers

        form_data
      end

      def merge_date_helpers
        @form_data['institutionDetails']['termStartDate'] =
          format_date(@form_data['institutionDetails']['termStartDate'])
        @form_data['studentRatioCalcChapter']['dateOfCalculation'] =
          format_date(@form_data['studentRatioCalcChapter']['dateOfCalculation'])
        @form_data['dateSigned'] = format_date(@form_data['dateSigned'])
      end

      def format_date(str)
        str.to_date.strftime(self.class.date_strftime)
      end
    end
  end
end
