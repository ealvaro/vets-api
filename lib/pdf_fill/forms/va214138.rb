# frozen_string_literal: true

require 'string_helpers'

module PdfFill
  module Forms
    class Va214138 < FormBase
      include ::PdfFill::Forms::FormHelper
      include ::PdfFill::Forms::FormHelper::PhoneNumberFormatting

      QUESTION_KEY = [
        { question_number: '1', question_text: "Veteran or Beneficiary's Name" },
        { question_number: '2', question_text: "Veteran's Social Security Number" },
        { question_number: '3', question_text: 'VA File Number' },
        { question_number: '4', question_text: "Veteran's Date of Birth" },
        { question_number: '5', question_text: "Veteran's Service Number" },
        { question_number: '6', question_text: "Claimant's Phone Number" },
        { question_number: '7', question_text: "Claimant's E-Mail Address" },
        { question_number: '8', question_text: "Claimant's Address" },
        { question_number: '9', question_text: 'Remarks' },
        { question_number: '10', question_text: "Remarks (Cont'd)" }
      ].freeze

      # because multiple forms will render the 4138
      # and their schemas may differ
      # we provide this interface,
      # to improve confidence that the renderer
      # sends the fields we care about here
      PdfSchema = Dry::Schema.Params do
        required(:claimantFullName).hash do
          required(:first).filled(:string)
          optional(:middle).maybe(:string)
          required(:last).filled(:string)
        end

        required(:veteranSocialSecurityNumber).filled(:string)

        optional(:vaFileNumber).maybe(:string)

        required(:veteranDateOfBirth).hash do
          required(:month).filled(:string)
          required(:day).filled(:string)
          required(:year).filled(:string)
        end

        optional(:veteranServiceNumber).maybe(:string)

        # phone numbers might be strings, or hashes, depending on the schema version
        # we support both
        optional(:claimantPhone).value((Dry::Types['string'] | Dry::Types['hash']).optional)
        optional(:claimantInternationalPhone).value((Dry::Types['string'] | Dry::Types['hash']).optional)

        optional(:claimantEmailAddress).maybe(:string)

        required(:claimantAddress).hash do
          required(:street).filled(:string)
          optional(:street2).maybe(:string)
          required(:city).filled(:string)
          optional(:state).maybe(:string)
          optional(:country).maybe(:string)
          required(:postalCode).filled(:string)
        end

        required(:remarks).filled(:string)
        optional(:remarksContinued).maybe(:string)
      end

      KEY = {
        'claimantFullName' => {
          'first' => {
            key: 'form1[0].#subform[0].Veterans_Beneficiary_First_Name[0]',
            limit: 12,
            question_num: 1,
            question_text: "VETERAN/BENEFICIARY'S FIRST NAME"
          },
          'middleInitial' => {
            question_num: 1,
            key: 'form1[0].#subform[0].Middle_Initial1[0]'
          },
          'last' => {
            key: 'form1[0].#subform[0].Last_Name[0]',
            limit: 18,
            question_num: 1,
            question_text: "VETERAN/BENEFICIARY'S LAST NAME"
          }
        },
        'veteranSocialSecurityNumber' => {
          'first' => {
            question_num: 2,
            key: 'form1[0].#subform[0].SocialSecurityNumber_FirstThreeNumbers[0]'
          },
          'second' => {
            question_num: 2,
            key: 'form1[0].#subform[0].SocialSecurityNumber_SecondTwoNumbers[0]'
          },
          'third' => {
            question_num: 2,
            key: 'form1[0].#subform[0].SocialSecurityNumber_LastFourNumbers[0]'
          }
        },
        'pageTwoVeteranSocialSecurityNumber' => {
          'first' => {
            key: 'form1[0].#subform[1].SocialSecurityNumber_FirstThreeNumbers[1]'
          },
          'second' => {
            key: 'form1[0].#subform[1].SocialSecurityNumber_SecondTwoNumbers[1]'
          },
          'third' => {
            key: 'form1[0].#subform[1].SocialSecurityNumber_LastFourNumbers[1]'
          }
        },
        'vaFileNumber' => {
          key: 'form1[0].#subform[0].VA_File_Number_If_Applicable[0]',
          question_text: 'V. A. File Number (If applicable). Enter 9 digits file number.'
        },
        'veteranDateOfBirth' => {
          'month' => {
            key: 'form1[0].#subform[0].Veterans_DOB_Month[0]'
          },
          'day' => {
            key: 'form1[0].#subform[0].DOB_Day[0]'
          },
          'year' => {
            key: 'form1[0].#subform[0].DOB_Year[0]'
          }
        },
        'veteranServiceNumber' => {
          key: 'form1[0].#subform[0].Veterans_Service_Number_If_Applicable[0]',
          question_text: "Veteran's Service Number (If applicable). Enter 9 digits."
        },
        'claimantPhone' => {
          'phone_area_code' => {
            key: 'form1[0].#subform[0].TelephoneNumber_FirstThreeNumbers[0]',
            limit: 3,
            question_num: 6,
            question_suffix: 'A',
            question_text: 'TELEPHONE NUMBER (Include Area Code). Enter three digits of Area Code.'
          },
          'phone_first_three_numbers' => {
            key: 'form1[0].#subform[0].TelephoneNumber_SecondThreeNumbers[0]',
            limit: 3,
            question_num: 6,
            question_suffix: 'B',
            question_text: 'TELEPHONE NUMBER (Include Area Code). Enter middle three digits.'
          },
          'phone_last_four_numbers' => {
            key: 'form1[0].#subform[0].TelephoneNumber_LastFourNumbers[0]',
            limit: 4,
            question_num: 6,
            question_suffix: 'C',
            question_text: 'TELEPHONE NUMBER (Include Area Code). Enter last four digits.'
          }
        },
        'claimantInternationalPhone' => {
          key: 'form1[0].#subform[0].International_Phone_Number[0]'
        },
        'claimantEmailAddress' => {
          'first' => {
            key: 'form1[0].#subform[0].EMAIL_ADDRESS[0]',
            limit: 20,
            question_num: 7,
            question_text: 'E-MAIL ADDRESS (Optional). Line 1 of 2. 20 characters max.'
          },
          'second' => {
            key: 'form1[0].#subform[0].EMAIL_ADDRESS[1]',
            limit: 20,
            question_num: 7,
            question_text: 'E-MAIL ADDRESS (Optional). Line 2 of 2. 20 characters max.'
          }
        },
        'claimantAddress' => {
          question_num: 8,
          question_text: 'MAILING ADDRESS',
          'street' => {
            key: 'form1[0].#subform[0].MailingAddress_NumberAndStreet[0]',
            limit: 30,
            question_num: 8,
            question_suffix: 'A',
            question_text: 'Number and Street'
          },
          'street2' => {
            key: 'form1[0].#subform[0].MailingAddress_ApartmentOrUnitNumber[0]',
            limit: 5,
            question_num: 8,
            question_suffix: 'B',
            question_text: 'Apartment or Unit Number'
          },
          'city' => {
            key: 'form1[0].#subform[0].MailingAddress_City[0]',
            limit: 18,
            question_num: 8,
            question_suffix: 'C',
            question_text: 'City'
          },
          'state' => {
            key: 'form1[0].#subform[0].MailingAddress_StateOrProvince[0]',
            limit: 2
          },
          'country' => {
            key: 'form1[0].#subform[0].MailingAddress_Country[0]'
          },
          'postalCode' => {
            'firstFive' => {
              key: 'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]'
            },
            'lastFour' => {
              key: 'form1[0].#subform[0].MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]'
            }
          }
        },
        'remarks' => {
          key: 'form1[0].#subform[0].REMARKS[0]',
          question_num: 9,
          limit: 1450,
          question_text: 'REMARKS (The following statement is made in connection with a ' \
                         'claim for benefits in the case of the above named veteran / beneficiary).'
        },
        'remarksContinued' => {
          key: 'form1[0].#subform[1].REMARKS[1]',
          question_num: 10,
          limit: 2109,
          question_text: 'REMARKS (Continued) (The following statement is made in connection with ' \
                         'a claim for benefits in the case of the above named veteran / beneficiary).'
        }
      }.freeze

      def merge_fields(_options = {})
        form_data[:claimantFullName] ||= {}
        form_data[:claimantFullName].merge!(
          {
            first: StringHelpers.titlecase_name(form_data.dig(:claimantFullName, :first)),
            middleInitial: StringHelpers.titlecase_name(form_data.dig(:claimantFullName, :middle)&.first),
            last: StringHelpers.titlecase_name(form_data.dig(:claimantFullName, :last))
          }
        )
        form_data[:veteranSocialSecurityNumber] = split_ssn(form_data[:veteranSocialSecurityNumber])
        form_data[:pageTwoVeteranSocialSecurityNumber] = form_data[:veteranSocialSecurityNumber]
        form_data[:veteranDateOfBirth] = split_date(form_data[:veteranDateOfBirth])
        form_data[:claimantAddress] ||= {}
        form_data[:claimantAddress][:postalCode] =
          split_postal_code(form_data[:claimantAddress])

        form_data[:claimantEmailAddress] = merge_email_address(form_data[:claimantEmailAddress])

        # NOTE: merge_remarks splits the (already-formatted) remarks string across the
        # REMARKS / REMARKS (Cont'd) fields. The result MUST be assigned back — a bare
        # `form_data.merge(...)` is non-destructive and silently drops the split, leaving
        # any text over 1450 chars off the rendered form.
        remarks_fields = merge_remarks(form_data[:remarks] || '')
        form_data.merge!(remarks_fields) if remarks_fields

        form_data[:claimantPhone] = expand_phone_number(form_data[:claimantPhone].to_s)
        form_data[:claimantInternationalPhone] = form_data[:claimantInternationalPhone].to_s

        form_data.deep_stringify_keys!
      end

      def merge_email_address(email)
        parts = (email || '').scan(/.{1,20}/)
        case parts.length
        when 0
          {}
        when 1
          { first: parts[0] }
        else
          { first: parts[0], second: parts[1] }
        end
      end

      # Splits the remarks string across the REMARKS (limit 1450) and
      # REMARKS (Cont'd) (limit 2109) fields. The caller is responsible for any
      # header/formatting of the remarks text itself (e.g. Cave::ChangeLog already
      # emits its own "SYSTEM GENERATED..." header), so this only chunks the string.
      def merge_remarks(remarks)
        remarks_parts = (remarks || '').scan(/.{1,1450}/m)
        case remarks_parts.length
        when 0 # empty string, no-op
          nil
        when 1
          { remarks: remarks_parts[0] }
        else
          {
            remarks: remarks_parts[0],
            remarksContinued: remarks_parts.drop(1).join
          }
        end
      end
    end
  end
end
