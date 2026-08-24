# frozen_string_literal: true

require 'active_support/number_helper'

module PdfFill
  module Forms
    class Va220803 < FormBase
      include FormHelper

      AGREEMENT_TYPES = {
        'startNewOpenEndedAgreement' => 'New open-ended agreement',
        'modifyExistingAgreement' => 'Modification to existing agreement',
        'withdrawFromYellowRibbonProgram' => 'Withdrawal of Yellow Ribbon agreement'
      }.freeze

      # Template PDF is 2 pages; overflow pages start at page 3.
      START_PAGE = 3

      # question_number matches the real printed question number on the 22-0803 form:
      # 11 = Remarks, under Part III - Test Information.
      QUESTION_KEY = [
        { question_number: '11', question_text: 'Remarks' }
      ].freeze

      # Groups overflow questions under the printed form's Part heading so the overflow
      # page renders a section header above the entry.
      SECTIONS = [
        {
          label: 'Part III - Test Information',
          question_nums: %w[11]
        }
      ].freeze

      KEY = {
        'bill_type_chapter_30' => {
          key: 'bill_type_chapter_30'
        },
        'bill_type_chapter_33' => {
          key: 'bill_type_chapter_33'
        },
        'bill_type_chapter_35' => {
          key: 'bill_type_chapter_35'
        },
        'bill_type_chapter_1606' => {
          key: 'bill_type_chapter_1606'
        },
        'applicantName' => {
          key: 'applicant_name'
        },
        'remarks' => {
          key: 'remarks',
          question_text: 'REMARKS (Optional)',
          question_num: 11,
          limit: 456,
          multiline_limit: 6
        },
        'mailingAddress' => {
          key: 'applicant_address'
        },
        'emailAddress' => {
          key: 'applicant_email'
        },
        'fileNumber' => {
          key: 'applicant_va_file_number'
        },
        'mobilePhone' => {
          key: 'applicant_mobile_phone'
        },
        'homePhone' => {
          key: 'applicant_home_phone'
        },
        'previously_applied_yes' => {
          key: 'previously_applied_yes'
        },
        'previously_applied_no' => {
          key: 'previously_applied_no'
        },
        'testName' => {
          key: 'test_name'
        },
        'testDate' => {
          key: 'test_date'
        },
        'testCost' => {
          key: 'test_cost'
        },
        'organizationInfo' => {
          key: 'certifying_name_and_address'
        },
        'statementOfTruthSignature' => {
          key: 'applicant_signature'
        },
        'dateSigned' => {
          key: 'date_signed'
        }
      }.freeze

      def merge_fields(_options = {})
        form_data = JSON.parse(JSON.generate(@form_data))

        form_data['applicantName'] = combine_full_name(form_data['applicantName'])
        form_data['mailingAddress'] = format_address(form_data['mailingAddress'])
        format_bill_type(form_data)
        format_file_number(form_data)
        format_previously_applied(form_data)
        format_organization_info(form_data)
        format_signature(form_data)
        format_test_cost(form_data)
        format_test_date(form_data)

        form_data
      end

      def format_bill_type(form_data)
        case form_data['vaBenefitProgram']
        when 'chapter30'
          form_data['bill_type_chapter_30'] = 'Yes'
        when 'chapter33'
          form_data['bill_type_chapter_33'] = 'Yes'
        when 'chapter35'
          form_data['bill_type_chapter_35'] = 'Yes'
        when 'chapter1606'
          form_data['bill_type_chapter_1606'] = 'Yes'
        end
      end

      def format_file_number(form_data)
        form_data['fileNumber'] = if form_data['vaFileNumber'].present? && form_data['vaBenefitProgram'] == 'chapter35'
                                    "#{format_ssn(form_data['vaFileNumber'])} #{form_data['payeeNumber']}"
                                  else
                                    format_ssn(form_data['ssn'])
                                  end
      end

      def format_previously_applied(form_data)
        if form_data['hasPreviouslyApplied']
          form_data['previously_applied_yes'] = 'Yes'
        else
          form_data['previously_applied_no'] = 'Yes'
        end
      end

      def format_organization_info(form_data)
        form_data['organizationInfo'] = <<~ORGINFO
          #{form_data['organizationName']}
          #{format_address(form_data['organizationAddress'])}
        ORGINFO
      end

      def format_signature(form_data)
        form_data['dateSigned'] = format_date(form_data['dateSigned'])
      end

      def format_test_cost(form_data)
        form_data['testCost'] = "$#{ActiveSupport::NumberHelper.number_to_delimited(form_data['testCost'])}"
      end

      def format_test_date(form_data)
        form_data['testDate'] = format_date(form_data['testDate'])
      end

      def format_date(date_str, format = '%m/%d/%Y')
        Date.parse(date_str).strftime(format)
      rescue
        date_str
      end

      def format_ssn(ssn_str)
        return '' if ssn_str.blank?

        [ssn_str[0..2],
         ssn_str[3..4],
         ssn_str[5..]].join('-')
      end

      def format_address(address)
        return if address.blank?

        postal_code = address['postalCode']
        postal_code = combine_postal_code(postal_code) if postal_code.is_a?(Hash)

        [
          address['street'],
          address['street2'],
          address['street3'],
          [address['city'], address['state'], postal_code, address['country']].compact_blank.join(', ')
        ].compact_blank.join("\n")
      end
    end
  end
end
