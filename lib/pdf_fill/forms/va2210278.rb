# frozen_string_literal: true

require 'pdf_fill/forms/form_base'
require 'pdf_fill/form_value'

module PdfFill
  module Forms
    class Va2210278 < FormBase
      ITERATOR = PdfFill::HashConverter::ITERATOR

      # Template PDF is 5 pages (2 pages of static instructions, 2 fillable pages, 1 page of
      # static privacy act info); overflow pages start at page 6.
      START_PAGE = 6

      # Section I (Claimant's Identifying Information) has no fields that can realistically
      # overflow (see QUESTION_KEY comment below), so it's omitted here; empty sections never
      # render a header on the extras page since headers only render for sections with content.
      SECTIONS = [
        {
          label: "Section II - Contact's Information",
          question_nums: %w[7 8a 8c]
        },
        {
          label: 'Section III - Declaration of Intent',
          question_nums: %w[13]
        }
      ].freeze

      # question_number values match the real printed question numbers on the 22-10278 form.
      # Only fields that can realistically overflow (per vets-json-schema maxLength/maxItems
      # constraints) are included: SSNs, VA file numbers, dates, and phone numbers have fixed
      # formats; the claim-information checkboxes and security question fields have no
      # character limit configured; and claimantAddress, thirdPartyPersonAddress (8B),
      # organizationAddress (8D), organizationRepresentatives, and otherText all have PDF field
      # limits that meet or exceed what the schema allows a real submission to contain (e.g.
      # claimantAddress's combined address lines cap out around 422 realistic characters,
      # under its 500-char PDF limit), so none of those can overflow.
      QUESTION_KEY = [
        { question_number: '7', question_text: 'Email Address' },
        { question_number: '8a', question_text: 'Name of Person to Receive Information' },
        { question_number: '8c', question_text: 'Name of Organization to Receive Information' },
        { question_number: '13', question_text: 'Claimant Signature' }
      ].freeze

      KEY = {
        'claimantPersonalInformation' => {
          'fullName' => {
            key: 'fullName',
            limit: 31,
            question_num: 1,
            question_text: 'NAME OF CLAIMANT'
          },
          'ssn' => {
            key: 'ssn',
            question_num: 2,
            question_text: 'SOCIAL SECURITY NUMBER'
          },
          'vaFileNumber' => {
            key: 'vaFileNumber',
            limit: 9,
            question_num: 3,
            question_text: 'VA FILE NUMBER'
          },
          'dateOfBirth' => {
            key: 'dateOfBirth',
            limit: 20,
            question_num: 4,
            question_text: 'DATE OF BIRTH'
          }
        },
        'claimantAddress' => {
          key: 'claimantAddress',
          limit: 500,
          question_num: 5,
          question_text: 'CLAIMANT ADDRESS'
        },
        'claimantContactInformation' => {
          'phoneNumber' => {
            key: 'phoneNumber',
            limit: 13,
            question_num: 6,
            question_text: 'PHONE NUMBER'
          },
          'emailAddress' => {
            key: 'emailAddress',
            limit: 30,
            question_num: 7,
            question_text: 'EMAIL ADDRESS'
          }
        },
        'thirdPartyPersonName' => {
          key: 'thirdPartyPersonName',
          limit: 12,
          question_num: 8,
          question_suffix: 'A',
          question_text: 'NAME OF PERSON TO RECEIVE INFORMATION',
          show_suffix: true
        },
        'thirdPartyPersonAddress' => {
          key: 'thirdPartyPersonAddress',
          limit: 500,
          question_num: 8,
          question_suffix: 'B',
          question_text: 'ADDRESS OF PERSON TO RECEIVE INFORMATION',
          show_suffix: true
        },
        'thirdPartyOrganizationInformation' => {
          'organizationName' => {
            key: 'organizationName',
            limit: 30,
            question_num: 8,
            question_suffix: 'C',
            question_text: 'NAME OF ORGANIZATION TO RECEIVE INFORMATION',
            show_suffix: true
          },
          'organizationAddress' => {
            key: 'organizationAddress',
            limit: 300,
            question_num: 8,
            question_suffix: 'D',
            question_text: 'ADDRESS OF ORGANIZATION TO RECEIVE INFORMATION',
            show_suffix: true
          }
        },
        'organizationRepresentatives' => {
          limit: 6,
          first_key: 'name',
          name: {
            key: "organizationRepresentatives#{ITERATOR}",
            limit: 160,
            question_num: 12,
            question_text: 'ADDITIONAL ORGANIZATION REPRESENTATIVES (ITEM 8C CONTINUED)'
            # iterator: ITERATOR
          }
        },
        'claimInformation' => {
          'statusOfClaim' => {
            key: 'statusOfClaim',
            question_num: 10,
            question_text: 'STATUS OF CLAIM'
          },
          'currentBenefit' => {
            key: 'currentBenefit',
            question_num: 10,
            question_text: 'CURRENT BENEFIT'
          },
          'paymentHistory' => {
            key: 'paymentHistory',
            question_num: 10,
            question_text: 'PAYMENT HISTORY'
          },
          'amountOwed' => {
            key: 'amountOwed',
            question_num: 10,
            question_text: 'AMOUNT OWED'
          },
          'minor' => {
            key: 'minor',
            question_num: 10,
            question_text: 'MINOR'
          },
          'other' => {
            key: 'other',
            question_num: 10,
            question_text: 'OTHER'
          },
          'otherText' => {
            key: 'otherText',
            limit: 30,
            question_num: 10,
            question_text: 'OTHER TEXT'
          }
        },
        'isLimited' => {
          key: 'isLimited',
          question_num: 9,
          question_text: 'IS LIMITED'
        },
        'isNotLimited' => {
          key: 'isNotLimited',
          question_num: 9,
          question_text: 'IS NOT LIMITED'
        },
        'lengthOfRelease' => {
          'isOngoing' => {
            key: 'isOngoing',
            question_num: 11,
            question_text: 'IS ONGOING'
          },
          'isDated' => {
            key: 'isDated',
            question_num: 11,
            question_text: 'IS DATED'
          },
          'releaseDate' => {
            key: 'releaseDate',
            question_num: 11,
            question_text: 'RELEASE DATE'
          }
        },
        'securityQuestion' => {
          key: 'question',
          question_num: 12,
          question_suffix: 'A',
          question_text: 'SECURITY QUESTION'
        },
        'securityAnswer' => {
          key: 'answer',
          question_num: 12,
          question_suffix: 'B',
          question_text: 'SECURITY ANSWER'
        },
        'statementOfTruthSignature' => {
          key: 'statementOfTruthSignature',
          limit: 50,
          question_num: 13,
          question_text: 'STATEMENT OF TRUTH SIGNATURE'
        },
        'dateSigned' => {
          key: 'dateSigned',
          limit: 20,
          question_num: 14,
          question_text: 'DATE SIGNED'
        },
        'ssn2' => {
          key: 'ssn2',
          question_num: 2,
          question_text: 'SSN PART 2'
        },
        'ssn3' => {
          key: 'ssn3',
          question_num: 2,
          question_text: 'SSN PART 3'
        }
      }.freeze

      SECURITY_QUESTIONS = {
        'pin' => 'I would like to use a pin or password',
        'motherBornLocation' => 'The city and state your mother was born in',
        'highSchool' => 'The name of the high school you attended',
        'petName' => 'Your first pet\'s name',
        'teacherName' => 'Your favorite teacher\'s name',
        'fatherMiddleName' => 'Your father\'s middle name'
      }.freeze

      def merge_fields(_options = {})
        @form_data = @form_data.deep_dup

        merge_claimant_personal_info
        merge_claimant_address
        merge_third_party_info
        merge_organization_info
        merge_claim_information
        merge_length_of_release
        merge_security_info

        @form_data['dateSigned'] = format_date(@form_data['dateSigned']) if @form_data['dateSigned']

        @form_data
      end

      private

      def merge_claimant_personal_info
        return unless @form_data['claimantPersonalInformation']

        person = @form_data['claimantPersonalInformation']

        if person['fullName']
          @form_data['claimantPersonalInformation']['fullName'] = combine_full_name(person['fullName'])
        end

        if person['ssn']
          ssn = format_ssn(person['ssn'])
          @form_data['claimantPersonalInformation']['ssn'] = ssn
          @form_data['ssn2'] = ssn
          @form_data['ssn3'] = ssn
        end

        return unless person['dateOfBirth']

        @form_data['claimantPersonalInformation']['dateOfBirth'] = format_date(person['dateOfBirth'])
      end

      def merge_claimant_address
        return unless @form_data['claimantAddress']

        addr = @form_data['claimantAddress']
        if addr.key?('addressLine1')
          mapped_addr = {
            'street' => addr['addressLine1'],
            'street2' => addr['addressLine2'],
            'street3' => addr['addressLine3'],
            'city' => addr['city'],
            'state' => addr['stateCode'],
            'postalCode' => addr['zipCode'],
            'country' => addr['countryName'] || addr['countryCodeIso3']
          }
          @form_data['claimantAddress'] = combine_full_address_extras(mapped_addr)
        else
          @form_data['claimantAddress'] = combine_full_address_extras(addr)
        end
      end

      def merge_third_party_info
        if @form_data['thirdPartyPersonAddress']
          @form_data['thirdPartyPersonAddress'] = combine_full_address_extras(@form_data['thirdPartyPersonAddress'])
        end

        return unless @form_data['thirdPartyPersonName']

        @form_data['thirdPartyPersonName'] = combine_full_name(@form_data['thirdPartyPersonName'])
      end

      def merge_organization_info
        if @form_data['thirdPartyOrganizationInformation']&.key?('organizationAddress')
          @form_data['thirdPartyOrganizationInformation']['organizationAddress'] =
            combine_full_address_extras(@form_data['thirdPartyOrganizationInformation']['organizationAddress'])
        end

        return unless @form_data['organizationRepresentatives']

        @form_data['organizationRepresentatives'] = @form_data['organizationRepresentatives'].map do |rep|
          {
            name: combine_full_name(rep['fullName'])
          }
        end
      end

      def merge_claim_information
        return unless @form_data['claimInformation']

        info = @form_data['claimInformation']
        has_any = false

        %w[statusOfClaim currentBenefit paymentHistory amountOwed minor other].each do |field|
          if info[field]
            info[field] = 'Yes'
            has_any = true
          else
            info[field] = nil
          end
        end

        if has_any
          @form_data['isLimited'] = 'Yes'
          @form_data['isNotLimited'] = nil
        else
          @form_data['isLimited'] = nil
          @form_data['isNotLimited'] = 'Yes'
        end
      end

      def merge_length_of_release
        return unless @form_data['lengthOfRelease']

        release = @form_data['lengthOfRelease']
        if release['lengthOfRelease'] == 'ongoing'
          @form_data['lengthOfRelease']['isOngoing'] = 'Yes'
          @form_data['lengthOfRelease']['isDated'] = nil
          @form_data['lengthOfRelease']['releaseDate'] = nil
        elsif release['lengthOfRelease'] == 'date'
          @form_data['lengthOfRelease']['isOngoing'] = nil
          @form_data['lengthOfRelease']['isDated'] = 'Yes'
          @form_data['lengthOfRelease']['releaseDate'] = format_date(release['date'])
        end
      end

      def merge_security_info
        merge_security_question
        merge_security_answer
      end

      def merge_security_question
        return unless @form_data['securityQuestion']

        q_key = @form_data['securityQuestion']['question']
        if q_key == 'create'
          if @form_data['securityAnswer'] && @form_data['securityAnswer']['securityAnswerCreate']
            @form_data['securityQuestion'] =
              @form_data['securityAnswer']['securityAnswerCreate']['question']
          end
        else
          @form_data['securityQuestion'] = SECURITY_QUESTIONS[q_key]
        end
      end

      def merge_security_answer
        return unless @form_data['securityAnswer']

        ans = @form_data['securityAnswer']
        if ans['securityAnswerText']
          @form_data['securityAnswer'] = ans['securityAnswerText']
        elsif ans['securityAnswerLocation']
          loc = ans['securityAnswerLocation']
          @form_data['securityAnswer'] = "#{loc['city']}, #{loc['state']}"
        elsif ans['securityAnswerCreate']
          @form_data['securityAnswer'] = ans['securityAnswerCreate']['answer']
        else
          @form_data['securityAnswer'] = ans.to_s
        end
      end

      def format_date(date_str)
        return nil if date_str.blank?

        Date.parse(date_str).strftime('%m/%d/%Y')
      rescue ArgumentError
        date_str
      end

      def format_ssn(ssn_str)
        return '' if ssn_str.blank?

        [ssn_str[0..2],
         ssn_str[3..4],
         ssn_str[5..]].join('-')
      end
    end
  end
end
