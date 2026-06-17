# frozen_string_literal: true

require 'claims_api/v2/poa_pdf_constructor/base'

module ClaimsApi
  module V2
    module PoaPdfConstructor
      class Organization < ClaimsApi::V2::PoaPdfConstructor::Base
        def self.signature_coordinates
          if Flipper.enabled?(:lighthouse_claims_api_2122_pdf_form_update)
            { veteran: { x: 35, y: 305 }, representative: { x: 35, y: 265 } }
          else
            { veteran: { x: 35, y: 240 }, representative: { x: 35, y: 200 } }
          end
        end

        protected

        def page1_template_path
          page_template_base_path.join('1.pdf')
        end

        def page2_template_path
          page_template_base_path.join('2.pdf')
        end

        def page3_template_path
          page_template_base_path.join('3.pdf')
        end

        def page4_template_path
          page_template_base_path.join('4.pdf')
        end

        def page_template_base_path
          if Flipper.enabled?(:lighthouse_claims_api_2122_pdf_form_update)
            Rails.root.join('modules', 'claims_api', 'config', 'pdf_templates', '21-22', 'rev_10_27_2023')
          else
            Rails.root.join('modules', 'claims_api', 'config', 'pdf_templates', '21-22')
          end
        end

        #
        # Add text signature to pdf page .
        #
        # @param data [Hash] Hash of data to add to the pdf
        def sign_pdf_text(data)
          @page1_path = page1_template_path
          @page2_path = insert_text_signatures(page2_template_path, data['text_signatures']['page2'])
          @page3_path = page3_template_path
          @page4_path = page4_template_path
        end

        # rubocop:disable Layout/LineLength
        # rubocop:disable Metrics/MethodLength
        def page2_options(data)
          if Flipper.enabled?(:lighthouse_claims_api_2122_pdf_form_update)
            base_form = 'form1[0].#subform[1]'
            {
              # Header
              "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]": data.dig('veteran', 'ssn')[0..2],
              "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]": data.dig('veteran', 'ssn')[3..4],
              "#{base_form}.SocialSecurityNumber_LastFourNumbers[1]": data.dig('veteran', 'ssn')[5..8],
              # Section IV
              # Item 19
              "#{base_form}.I_Authorize[0]": data['recordConsent'] == true ? 1 : 0,
              # Item 20
              "#{base_form}.Drug_Abuse[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'DRUG_ABUSE'),
              "#{base_form}.Alcoholism_Or_Alcohol_Abuse[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'ALCOHOLISM'),
              "#{base_form}.Infection_With_The_Human_Immunodeficiency_Virus_HIV[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'HIV'),
              "#{base_form}.sicklecellanemia[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'SICKLE_CELL'),
              # Item 21
              "#{base_form}.I_Authorize[1]": data['consentAddressChange'] == true ? 1 : 0,
              # Item 22B
              "#{base_form}.DateSigned[0]": I18n.l(data['appointmentDate'].to_date, format: :va_form),
              # Item 23B
              "#{base_form}.DateSigned[1]": I18n.l(data['appointmentDate'].to_date, format: :va_form)
            }
          else
            base_form = 'F[0].Page_2[0]'
            {
              # Header
              "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
              "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
              "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
              # Section IV
              # Item 19
              "#{base_form}.I_Authorize[1]": data['recordConsent'] == true ? 1 : 0,
              # Item 20
              "#{base_form}.Drug_Abuse[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'DRUG_ABUSE'),
              "#{base_form}.Alcoholism_Or_Alcohol_Abuse[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'ALCOHOLISM'),
              "#{base_form}.Infection_With_The_Human_Immunodeficiency_Virus_HIV[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'HIV'),
              "#{base_form}.sicklecellanemia[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'SICKLE_CELL'),
              # Item 21
              "#{base_form}.I_Authorize[0]": data['consentAddressChange'] == true ? 1 : 0,
              # Item 22B
              "#{base_form}.Date_Signed[0]": I18n.l(data['appointmentDate'].to_date, format: :va_form),
              # Item 23B
              "#{base_form}.Date_Signed[1]": I18n.l(data['appointmentDate'].to_date, format: :va_form)
            }
          end
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def page1_options(data)
          if Flipper.enabled?(:lighthouse_claims_api_2122_pdf_form_update)
            base_form = 'form1[0].#subform[0]'
            {
              # Section I
              # Item 1
              "#{base_form}.VeteransFirstName[0]": data.dig('veteran', 'firstName'),
              "#{base_form}.VeteransLastName[0]": data.dig('veteran', 'lastName'),
              # Item 2
              "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
              "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
              "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
              # Item 4
              "#{base_form}.DOBmonth[0]": data.dig('veteran', 'birthdate').split('-').second,
              "#{base_form}.DOBday[0]": data.dig('veteran', 'birthdate').split('-').last.first(2),
              "#{base_form}.DOByear[0]": data.dig('veteran', 'birthdate').split('-').first,
              # Item 5
              "#{base_form}.InsuranceNumber_s[0]": data.dig('veteran', 'insuranceNumber'),
              # Item 7
              "#{base_form}.Claimants_MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'addressLine1'),
              "#{base_form}.Claimants_MailingAddress_ApartmentOrUnitNumber[0]": data.dig('veteran', 'address', 'addressLine2'),
              "#{base_form}.Claimants_MailingAddress_City[0]": data.dig('veteran', 'address', 'city'),
              "#{base_form}.Claimants_MailingAddress_StateOrProvince[0]": data.dig('veteran', 'address', 'stateCode'),
              "#{base_form}.Claimants_MailingAddress_Country[0]": data.dig('veteran', 'address', 'countryCode'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('veteran', 'address', 'zipCode'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('veteran', 'address', 'zipCodeSuffix'),
              # Item 8
              "#{base_form}.Phone[0]": handle_country_code(data.dig('veteran', 'phone')),
              # Item 9
              "#{base_form}.EmailAddress_Optional[0]": data.dig('veteran', 'email'),

              # Section II
              # Item 10
              "#{base_form}.Claimants_FirstName[0]": data.dig('dependent', 'first_name'),
              "#{base_form}.Claimants_LastName[0]": data.dig('dependent', 'last_name'),
              # Item 11
              "#{base_form}.DOBmonth[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.second,
              "#{base_form}.DOBday[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.last&.first(2),
              "#{base_form}.DOByear[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.first,
              "#{base_form}.Relationship_To_Veteran[0]": data.dig('claimant', 'relationship'),
              # Item 12
              "#{base_form}.Claimants_MailingAddress_NumberAndStreet[1]": data.dig('claimant', 'address', 'addressLine1'),
              "#{base_form}.Claimants_MailingAddress_ApartmentOrUnitNumber[1]": data.dig('claimant', 'address', 'addressLine2'),
              "#{base_form}.Claimants_MailingAddress_City[1]": data.dig('claimant', 'address', 'city'),
              "#{base_form}.Claimants_MailingAddress_StateOrProvince[1]": data.dig('claimant', 'address', 'stateCode'),
              "#{base_form}.Claimants_MailingAddress_Country[1]": data.dig('claimant', 'address', 'countryCode'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('claimant', 'address', 'zipCode'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]": data.dig('claimant', 'address', 'zipCodeSuffix'),
              # Item 13
              "#{base_form}.Phone[1]": handle_country_code(data.dig('claimant', 'phone')),
              # Item 14
              "#{base_form}.EmailAddress_Optional[1]": data.dig('claimant', 'email')&.downcase,

              # Section III
              # Item 15
              "#{base_form}.Name_Of_Service_Organization[0]": data.dig('serviceOrganization', 'organizationName'),
              # Item 16A
              "#{base_form}.Name_Of_Official_Representative[0]": "#{data.dig('serviceOrganization', 'firstName')} #{data.dig('serviceOrganization', 'lastName')}",
              # Item 16B
              "#{base_form}.Job_Title_Of_Person_Named_In_Item15A[0]": data.dig('serviceOrganization', 'jobTitle'),
              # Item 17
              "#{base_form}.Email_Address[0]": data.dig('serviceOrganization', 'email'),
              # Item 18
              "#{base_form}.DateAppt[0]": I18n.l(data['appointmentDate'].to_date, format: :va_form)
            }
          else
            base_form = 'F[0].Page_1[0]'
            {
              # Section I
              # Item 1
              "#{base_form}.VeteransLastName[0]": data.dig('veteran', 'lastName'),
              "#{base_form}.VeteransFirstName[0]": data.dig('veteran', 'firstName'),
              # Item 2
              "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
              "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
              "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
              # Item 4
              "#{base_form}.DOBmonth[0]": data.dig('veteran', 'birthdate').split('-').second,
              "#{base_form}.DOBday[0]": data.dig('veteran', 'birthdate').split('-').last.first(2),
              "#{base_form}.DOByear[0]": data.dig('veteran', 'birthdate').split('-').first,
              # Item 5
              "#{base_form}.InsuranceNumber_s[0]": data.dig('veteran', 'insuranceNumber'),
              # Item 7
              "#{base_form}.Veterans_MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'addressLine1'),
              "#{base_form}.Claimants_MailingAddress_ApartmentOrUnitNumber[1]": data.dig('veteran', 'address', 'addressLine2'),
              "#{base_form}.Claimants_MailingAddress_City[1]": data.dig('veteran', 'address', 'city'),
              "#{base_form}.Claimants_MailingAddress_StateOrProvince[1]": data.dig('veteran', 'address', 'stateCode'),
              "#{base_form}.Claimants_MailingAddress_Country[1]": data.dig('veteran', 'address', 'country'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('veteran', 'address', 'zipCode'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]": data.dig('veteran', 'address', 'zipCodeSuffix'),
              # Item 8
              "#{base_form}.TelephoneNumber_IncludeAreaCode[1]": handle_country_code(data.dig('veteran', 'phone')),
              # Item 9
              "#{base_form}.EmailAddress_Optional[0]": data.dig('veteran', 'email'),

              # Section II
              # Item 10
              "#{base_form}.Claimants_FirstName[0]": data.dig('dependent', 'first_name'),
              "#{base_form}.Claimants_LastName[0]": data.dig('dependent', 'last_name'),
              # Item 11
              "#{base_form}.Claimants_MailingAddress_NumberAndStreet[0]": data.dig('claimant', 'address', 'addressLine1'),
              "#{base_form}.Claimants_MailingAddress_ApartmentOrUnitNumber[0]": data.dig('claimant', 'address', 'addressLine2'),
              "#{base_form}.Claimants_MailingAddress_City[0]": data.dig('claimant', 'address', 'city'),
              "#{base_form}.Claimants_MailingAddress_StateOrProvince[0]": data.dig('claimant', 'address', 'stateCode'),
              "#{base_form}.Claimants_MailingAddress_Country[0]": data.dig('claimant', 'address', 'country'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('claimant', 'address', 'zipCode'),
              "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('address', 'zipCodeSuffix'),
              # Item 12
              "#{base_form}.TelephoneNumber_IncludeAreaCode[0]": handle_country_code(data.dig('claimant', 'phone')),
              # Item 13
              "#{base_form}.Claimants_EmailAddress_Optional[0]": data.dig('claimant', 'email')&.downcase,
              # Item 14
              "#{base_form}.Relationship_To_Veteran[0]": data.dig('claimant', 'relationship'),

              # Section III
              # Item 15
              "#{base_form}.Name_Of_Service_Organization[0]": data.dig('serviceOrganization', 'organizationName'),
              # Item 16A
              "#{base_form}.Name_Of_Official_Representative[0]": "#{data.dig('serviceOrganization', 'firstName')} #{data.dig('serviceOrganization', 'lastName')}",
              # Item 16B
              "#{base_form}.Job_Title_Of_Person_Named_In_Item15A[0]": data.dig('serviceOrganization', 'jobTitle'),
              # Item 17
              "#{base_form}.Email_Address[0]": data.dig('serviceOrganization', 'email'),
              # Item 18
              "#{base_form}.Date_Of_This_Appointment[0]": I18n.l(data['appointmentDate'].to_date, format: :va_form)
            }
          end
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Layout/LineLength
      end
    end
  end
end
