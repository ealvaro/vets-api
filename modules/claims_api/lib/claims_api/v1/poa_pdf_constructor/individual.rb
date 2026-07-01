# frozen_string_literal: true

require 'claims_api/v1/poa_pdf_constructor/base'
require 'claims_api/v1/poa_pdf_constructor/signature'

module ClaimsApi
  module V1
    module PoaPdfConstructor
      class Individual < ClaimsApi::V1::PoaPdfConstructor::Base
        protected

        def use_updated_form?
          return @use_updated_form unless @use_updated_form.nil?

          @use_updated_form = Flipper.enabled?(:lighthouse_claims_api_v1_2122a_pdf_form_update)
        end

        def page_template_base_path
          path = Rails.root.join('modules', 'claims_api', 'config', 'pdf_templates', '21-22A')
          use_updated_form? ? path.join('rev_07_2023') : path
        end

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
          nil
        end

        def page1_signatures(signatures)
          return updated_page1_signatures(signatures) if use_updated_form?

          legacy_page1_signatures(signatures)
        end

        def updated_page1_signatures(_signatures)
          [] # No signatures on page 1 of rev_07_2023
        end

        def legacy_page1_signatures(signatures)
          [
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['veteran'], x: 35, y: 90),
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['representative'], x: 35, y: 118)
          ]
        end

        def page2_signatures(signatures)
          return updated_page2_signatures(signatures) if use_updated_form?

          legacy_page2_signatures(signatures)
        end

        def updated_page2_signatures(_signatures)
          [] # No signatures on page 2 of rev_07_2023 (moved to page 3)
        end

        def legacy_page2_signatures(signatures)
          [
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['veteran'], x: 35, y: 322),
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['representative'], x: 35, y: 216)
          ]
        end

        def page2_options(data)
          return updated_page2_options(data) if use_updated_form?

          legacy_page2_options(data)
        end

        def updated_page2_options(data) # rubocop:disable Metrics/MethodLength
          base_form = 'form1[0].#subform[1]'
          {
            # Header
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[1]": data.dig('veteran', 'ssn')[5..8],
            # Item 16C - Representative Address
            "#{base_form}.MailingAddress_NumberAndStreet[2]": data.dig(
              'serviceOrganization', 'address', 'numberAndStreet'
            ),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[2]": data.dig(
              'serviceOrganization', 'address', 'aptUnitNumber'
            ),
            "#{base_form}.MailingAddress_City[2]": data.dig('serviceOrganization', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[2]": data.dig('serviceOrganization', 'address', 'state'),
            "#{base_form}.MailingAddress_Country[2]": data.dig('serviceOrganization', 'address', 'country'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[2]": data.dig(
              'serviceOrganization', 'address', 'zipFirstFive'
            ),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_LastFourNumbers[2]": data.dig(
              'serviceOrganization', 'address', 'zipLastFour'
            ),
            # Item 19a - Disclosure to affiliated personnel
            "#{base_form}.Checkbox_I_Authorize_VA_To_Disclose_All_My_Records_Other_Than_As_Provided_In_Items_20_And_21[0]": data['consentDisclosureAffiliated'] == true ? 1 : 0, # rubocop:disable Layout/LineLength
            "#{base_form}.Provide_The_Name_Of_The_Firm_Or_Organization_Here[0]": data['firmOrOrgName'],
            # Item 19b - Disclosure to named individuals
            "#{base_form}.Checkbox_I_Authorize_VA_To_Disclose_All_My_Records_Other_Than_As_Provided_In_Items_20_And_21[1]": data['consentDisclosureIndividuals'] == true ? 1 : 0, # rubocop:disable Layout/LineLength
            "#{base_form}.Provide_The_Names_Of_The_Individuals_Here[0]": data['individualNames']&.join(', '),
            # Item 20 - Record Consent
            "#{base_form}.AuthorizationForRepAccessToRecords[0]": data['recordConsent'] == true ? 1 : 0,
            # Item 21 - Limitation of Consent
            "#{base_form}.RelationshipToVeteran[1]": data['consentLimits']&.join(', '),
            # Item 22 - Address Change Authorization
            "#{base_form}.AuthorizationForRepActClaimantsBehalf[0]": data['consentAddressChange'] == true ? 1 : 0
          }
        end

        def legacy_page2_options(data)
          base_form = 'form1[0].#subform[1]'
          {
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[1]": data.dig('veteran', 'ssn')[5..8],
            "#{base_form}.AuthorizationForRepAccessToRecords[0]": data['recordConsent'] == true ? 1 : 0,
            "#{base_form}.AuthorizationForRepActClaimantsBehalf[0]": data['consentAddressChange'] == true ? 1 : 0,
            "#{base_form}.Date_Signed[0]": I18n.l(Time.zone.now.to_date, format: :va_form),
            "#{base_form}.Date_Signed[1]": I18n.l(Time.zone.now.to_date, format: :va_form),
            "#{base_form}.LIMITATIONOFCONSENT[0]": data['consentLimits']&.join(', ')
          }
        end

        def page3_options(data)
          return updated_page3_options(data) if use_updated_form?

          {} # legacy form has no page 3 fields
        end

        def updated_page3_options(data)
          base_form = 'form1[0].#subform[2]'
          today = Time.zone.now.to_date
          {
            # Header
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[2]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[2]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[2]": data.dig('veteran', 'ssn')[5..8],
            # Item 23B - Date Signed (Veteran/Claimant)
            "#{base_form}.Date_Signed_Month[2]": today.strftime('%m'),
            "#{base_form}.Date_Signed_Day[2]": today.strftime('%d'),
            "#{base_form}.Date_Signed_Year[2]": today.strftime('%Y'),
            # Item 25B - Date Signed (Representative)
            "#{base_form}.Date_Signed_Month[3]": today.strftime('%m'),
            "#{base_form}.Date_Signed_Day[3]": today.strftime('%d'),
            "#{base_form}.Date_Signed_Year[3]": today.strftime('%Y')
          }
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Layout/LineLength
        def page1_options(data)
          return updated_page1_options(data) if use_updated_form?

          legacy_page1_options(data)
        end

        def updated_page1_options(data) # rubocop:disable Metrics/MethodLength
          base_form = 'form1[0].#subform[0]'
          vet_phone = data.dig('veteran', 'phone')
          claimant_phone = data.dig('claimant', 'phone')
          {
            # Section I
            # Item 1
            "#{base_form}.Veterans_First_Name[0]": data.dig('veteran', 'firstName'),
            "#{base_form}.Veterans_Last_Name[0]": data.dig('veteran', 'lastName'),
            # Item 2
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
            # Item 4 - DOB
            "#{base_form}.Date_Of_Birth_Month[0]": data.dig('veteran', 'birthdate')&.split('-')&.second,
            "#{base_form}.Date_Of_Birth_Day[0]": data.dig('veteran', 'birthdate')&.split('-')&.last&.first(2),
            "#{base_form}.Date_Of_Birth_Year[0]": data.dig('veteran', 'birthdate')&.split('-')&.first,
            # Item 5 - Service Number
            "#{base_form}.Veterans_Service_Number_If_Applicable[1]": data.dig('veteran', 'serviceNumber'),
            # Item 6 - Service Branch (radio button)
            "#{base_form}.RadioButtonList[1]": service_branch_radio_value(data.dig('veteran', 'serviceBranch')),
            # Item 7 - Veteran Address
            "#{base_form}.MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'numberAndStreet'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[0]": data.dig('veteran', 'address', 'aptUnitNumber'),
            "#{base_form}.MailingAddress_City[0]": data.dig('veteran', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[0]": data.dig('veteran', 'address', 'state'),
            "#{base_form}.MailingAddress_Country[0]": data.dig('veteran', 'address', 'country'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('veteran', 'address',
                                                                                        'zipFirstFive'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('veteran', 'address',
                                                                                       'zipLastFour'),
            # Item 8 - Veteran Phone
            "#{base_form}.Telephone_Number_Area_Code[1]": domestic_phone_part(vet_phone, 'areaCode'),
            "#{base_form}.Telephone_Middle_Three_Numbers[0]": domestic_phone_part(vet_phone, 'middleThree'),
            "#{base_form}.Telephone_Last_Four_Numbers[1]": domestic_phone_part(vet_phone, 'lastFour'),
            "#{base_form}.International_Telephone_Number_If_Applicable[0]": international_phone(vet_phone),
            # Item 9 - Veteran Email
            "#{base_form}.E_Mail_Address_Optional[1]": data.dig('veteran', 'email'),

            # Section II
            # Item 10 - Claimant Name
            "#{base_form}.Claimants_First_Name[0]": data.dig('claimant', 'firstName'),
            "#{base_form}.Claimants_Middle_Initial[0]": data.dig('claimant', 'middleInitial'),
            "#{base_form}.Claimants_Last_Name[0]": data.dig('claimant', 'lastName'),
            # Item 11 - Claimant DOB
            "#{base_form}.Claimants_Date_Of_Birth_Month[0]": data.dig('claimant', 'dateOfBirth')&.split('-')&.second,
            "#{base_form}.Date_Of_Birth_Day[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.last&.first(2),
            "#{base_form}.Date_Of_Birth_Year[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.first,
            # Item 12 - Relationship
            "#{base_form}.RelationshipToVeteran[0]": data.dig('claimant', 'relationship'),
            # Item 13 - Claimant Address
            "#{base_form}.MailingAddress_NumberAndStreet[1]": data.dig('claimant', 'address', 'numberAndStreet'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[1]": data.dig('claimant', 'address', 'aptUnitNumber'),
            "#{base_form}.MailingAddress_City[1]": data.dig('claimant', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[1]": data.dig('claimant', 'address', 'state'),
            "#{base_form}.MailingAddress_Country[1]": data.dig('claimant', 'address', 'country'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('claimant', 'address',
                                                                                        'zipFirstFive'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]": data.dig('claimant', 'address',
                                                                                       'zipLastFour'),
            # Item 14 - Claimant Phone
            "#{base_form}.Telephone_Number_Area_Code[0]": domestic_phone_part(claimant_phone, 'areaCode'),
            "#{base_form}.Telphone_Middle_Three_Numbers[0]": domestic_phone_part(claimant_phone, 'middleThree'),
            "#{base_form}.Telephone_Last_Four_Numbers[0]": domestic_phone_part(claimant_phone, 'lastFour'),
            "#{base_form}.International_Telephone_Number_If_Applicable[1]": international_phone(claimant_phone),
            # Item 15 - Claimant Email
            "#{base_form}.E_Mail_Address_Optional[0]": data.dig('claimant', 'email'),

            # Section III
            # Item 16A - Representative Name
            "#{base_form}.Name_Of_Individual_Appointed_As_Representative_First_Name[0]": data.dig(
              'serviceOrganization', 'firstName'
            ),
            "#{base_form}.Last_Name[0]": data.dig('serviceOrganization', 'lastName'),
            # Item 16B - Representative Type (radio button)
            "#{base_form}.RadioButtonList[0]": rep_type_radio_value(data.dig('representative', 'type'))
          }
        end

        def legacy_page1_options(data)
          base_form = 'form1[0].#subform[0]'
          {
            # Veteran
            "#{base_form}.VeteransLastName[0]": data.dig('veteran', 'lastName'),
            "#{base_form}.VeteransFirstName[0]": data.dig('veteran', 'firstName'),
            "#{base_form}.TelephoneNumber_IncludeAreaCode[0]": handle_country_code(data.dig('veteran', 'phone')),
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
            "#{base_form}.DOBmonth[0]": data.dig('veteran', 'birthdate').split('-').second,
            "#{base_form}.DOBday[0]": data.dig('veteran', 'birthdate').split('-').last.first(2),
            "#{base_form}.DOByear[0]": data.dig('veteran', 'birthdate').split('-').first,
            "#{base_form}.Veterans_MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'numberAndStreet'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[1]": data.dig('veteran', 'address', 'aptUnitNumber'),
            "#{base_form}.MailingAddress_City[1]": data.dig('veteran', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[1]": data.dig('veteran', 'address', 'state'),
            "#{base_form}.MailingAddress_Country[1]": data.dig('veteran', 'address', 'country'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('veteran', 'address', 'zipFirstFive'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_ZIPOrPostalCode_LastFourNumbers[1]": data.dig('veteran', 'address', 'zipLastFour'),

            # Service Branch
            "#{base_form}.ARMYCheckbox1[0]": (data.dig('veteran', 'serviceBranch') == 'ARMY' ? 1 : 0),
            "#{base_form}.NAVYCheckbox2[0]": (data.dig('veteran', 'serviceBranch') == 'NAVY' ? 1 : 0),
            "#{base_form}.AIR_FORCECheckbox3[0]": (data.dig('veteran', 'serviceBranch') == 'AIR FORCE' ? 1 : 0),
            "#{base_form}.MARINE_CORPSCheckbox4[0]": (data.dig('veteran', 'serviceBranch') == 'MARINE CORPS' ? 1 : 0),
            "#{base_form}.COAST_GUARDCheckbox5[0]": (data.dig('veteran', 'serviceBranch') == 'COAST GUARD' ? 1 : 0),
            "#{base_form}.SPACE_FORCECheckbox3[0]": (data.dig('veteran', 'serviceBranch') == 'SPACE FORCE' ? 1 : 0),
            "#{base_form}.OTHER_Checkbox6[0]": (data.dig('veteran', 'serviceBranch') == 'OTHER' ? 1 : 0),
            "#{base_form}.JF15[0]": data.dig('veteran', 'serviceBranchOther'),

            # Claimant
            "#{base_form}.Claimants_First_Name[0]": data.dig('claimant', 'firstName'),
            "#{base_form}.Claimants_Last_Name[0]": data.dig('claimant', 'lastName'),
            "#{base_form}.Claimants_Middle_Initial1[0]": data.dig('claimant', 'middleInitial'),
            "#{base_form}.MailingAddress_NumberAndStreet[0]": data.dig('claimant', 'address', 'numberAndStreet'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[0]": data.dig('claimant', 'address', 'aptUnitNumber'),
            "#{base_form}.MailingAddress_City[0]": data.dig('claimant', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[0]": data.dig('claimant', 'address', 'state'),
            "#{base_form}.MailingAddress_Country[0]": data.dig('claimant', 'address', 'country'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('claimant', 'address', 'zipFirstFive'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('address', 'zipLastFour'),
            "#{base_form}.TelephoneNumber_IncludeAreaCode[1]": handle_country_code(data.dig('claimant', 'phone')),
            "#{base_form}.EmailAddress_Optional[1]": data.dig('claimant', 'email'),
            "#{base_form}.RelationshipToVeteran[0]": data.dig('claimant', 'relationship'),

            "#{base_form}.NAME_OF_INDIVIDUAL_APPOINTED_AS_REPRESENTATIVE[0]": "#{data.dig('serviceOrganization', 'firstName')} #{data.dig('serviceOrganization', 'lastName')}",
            # Item 15B
            "#{base_form}.Checkbox1[0]": (data.dig('representative', 'type') == 'attorney' ? 1 : 0),
            "#{base_form}.Checkbox2[0]": (data.dig('representative', 'type') == 'claim_agents' ? 1 : 0),
            # Item 18
            "#{base_form}.ADDRESSOFINDIVIDUALAPPOINTEDASCLAIMANTSREPRESENTATATIVE[0]": stringify_address(data.dig('serviceOrganization', 'address')),

            "#{base_form}.Date_Of_Signature[0]": I18n.l(Time.zone.now.to_date, format: :va_form),
            "#{base_form}.Date_Of_Signature[1]": I18n.l(Time.zone.now.to_date, format: :va_form)
          }
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Layout/LineLength

        SERVICE_BRANCH_RADIO_VALUES = {
          'ARMY' => 4, 'NAVY' => 5, 'AIR FORCE' => 6, 'MARINE CORPS' => 7,
          'COAST GUARD' => 8, 'SPACE FORCE' => 9, 'NOAA' => 10, 'USPHS' => 11
        }.freeze

        REP_TYPE_RADIO_VALUES = {
          'attorney' => 4, 'claim_agents' => 1
        }.freeze

        def service_branch_radio_value(branch)
          SERVICE_BRANCH_RADIO_VALUES[branch] || 'Off'
        end

        def rep_type_radio_value(type)
          REP_TYPE_RADIO_VALUES[type] || 'Off'
        end

        def domestic_phone?(phone)
          phone.present? && (phone['countryCode'].blank? || phone['countryCode'] == '1')
        end

        def domestic_phone_part(phone, part)
          return unless domestic_phone?(phone)

          digits = phone['phoneNumber']&.gsub(/\D/, '')
          case part
          when 'areaCode' then phone['areaCode']
          when 'middleThree' then digits&.[](0..2)
          when 'lastFour' then digits&.[](3..6)
          end
        end

        def international_phone(phone)
          return if phone.blank? || domestic_phone?(phone)

          "+#{phone['countryCode']} #{phone['areaCode']} #{phone['phoneNumber']}".strip
        end

        def page3_signatures(signatures)
          return [] unless use_updated_form?

          [
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['veteran'], x: 35, y: 642),
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['representative'], x: 35, y: 541)
          ]
        end

        private

        def sign_pdf(signatures)
          super
          return unless use_updated_form?

          @page3_path = insert_signatures(@page3_path, page3_signatures(signatures))
        end

        def fill_pdf(data)
          super
          return unless use_updated_form?

          pdftk = PdfForms.new(Settings.binaries.pdftk)
          temp_path = Rails.root.join('tmp', "poa_#{SecureRandom.uuid}_page_3.pdf")
          pdftk.fill_form(
            @page3_path,
            temp_path,
            page3_options(data),
            flatten: true
          )
          @page3_path = temp_path
        end
      end
    end
  end
end
