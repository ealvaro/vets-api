# frozen_string_literal: true

require 'claims_api/v2/poa_pdf_constructor/base'

module ClaimsApi
  module V2
    module PoaPdfConstructor
      class Individual < ClaimsApi::V2::PoaPdfConstructor::Base
        def self.signature_coordinates
          if Flipper.enabled?(:lighthouse_claims_api_2122a_pdf_form_update)
            { page: 'page3', veteran: { x: 35, y: 626 }, representative: { x: 35, y: 525 } }
          else
            { page: 'page2', veteran: { x: 35, y: 306 }, representative: { x: 35, y: 200 } }
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
          nil
        end

        def page_template_base_path
          path = Rails.root.join('modules', 'claims_api', 'config', 'pdf_templates', '21-22A')
          Flipper.enabled?(:lighthouse_claims_api_2122a_pdf_form_update) ? path.join('rev_07_2023') : path
        end

        #
        # Add text signature to pdf page .
        #
        # @param data [Hash] Hash of data to add to the pdf
        def sign_pdf_text(data)
          if Flipper.enabled?(:lighthouse_claims_api_2122a_pdf_form_update)
            updated_sign_pdf_text(data)
          else
            legacy_sign_pdf_text(data)
          end
        end

        def updated_sign_pdf_text(data)
          @page1_path = page1_template_path
          @page2_path = page2_template_path
          @page3_path = if data['text_signatures']&.key?('page3')
                          insert_text_signatures(page3_template_path, data['text_signatures']['page3'])
                        else
                          page3_template_path
                        end
          @page4_path = page4_template_path
        end

        def legacy_sign_pdf_text(data)
          @page1_path = page1_template_path
          @page2_path = insert_text_signatures(page2_template_path, data['text_signatures']['page2'])
          @page3_path = page3_template_path
          @page4_path = page4_template_path
        end

        def page2_options(data)
          return updated_page2_options(data) if Flipper.enabled?(:lighthouse_claims_api_2122a_pdf_form_update)

          legacy_page2_options(data)
        end

        def page3_options(data)
          return updated_page3_options(data) if Flipper.enabled?(:lighthouse_claims_api_2122a_pdf_form_update)

          {} # legacy form has no page 3 fields
        end

        def page1_options(data)
          return updated_page1_options(data) if Flipper.enabled?(:lighthouse_claims_api_2122a_pdf_form_update)

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
            # Item 6 - Service Branch (radio buttons)
            "#{base_form}.RadioButtonList[1]": service_branch_radio_value(data.dig('veteran', 'serviceBranch')),
            # Item 7 - Veteran Address
            "#{base_form}.MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'addressLine1'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[0]": data.dig('veteran', 'address', 'addressLine2'),
            "#{base_form}.MailingAddress_City[0]": data.dig('veteran', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[0]": data.dig('veteran', 'address', 'stateCode'),
            "#{base_form}.MailingAddress_Country[0]": data.dig('veteran', 'address', 'countryCode'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('veteran', 'address',
                                                                                        'zipCode'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('veteran', 'address',
                                                                                       'zipCodeSuffix'),
            # Item 8 - Veteran Phone
            "#{base_form}.Telephone_Number_Area_Code[1]": domestic_phone_part(vet_phone, 'areaCode'),
            "#{base_form}.Telephone_Middle_Three_Numbers[0]": domestic_phone_part(vet_phone, 'middleThree'),
            "#{base_form}.Telephone_Last_Four_Numbers[1]": domestic_phone_part(vet_phone, 'lastFour'),
            "#{base_form}.International_Telephone_Number_If_Applicable[0]": international_phone(vet_phone),
            # Item 9 - Veteran Email
            "#{base_form}.E_Mail_Address_Optional[1]": data.dig('veteran', 'email'),

            # Section II
            # Item 10 - Claimant Name
            "#{base_form}.Claimants_First_Name[0]": data.dig('dependent', 'first_name'),
            "#{base_form}.Claimants_Last_Name[0]": data.dig('dependent', 'last_name'),
            # Item 11 - Claimant DOB
            "#{base_form}.Claimants_Date_Of_Birth_Month[0]": data.dig('claimant', 'dateOfBirth')&.split('-')&.second,
            "#{base_form}.Date_Of_Birth_Day[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.last&.first(2),
            "#{base_form}.Date_Of_Birth_Year[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.first,
            # Item 12 - Relationship
            "#{base_form}.RelationshipToVeteran[0]": data.dig('claimant', 'relationship'),
            # Item 13 - Claimant Address
            "#{base_form}.MailingAddress_NumberAndStreet[1]": data.dig('claimant', 'address', 'addressLine1'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[1]": data.dig('claimant', 'address', 'addressLine2'),
            "#{base_form}.MailingAddress_City[1]": data.dig('claimant', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[1]": data.dig('claimant', 'address', 'stateCode'),
            "#{base_form}.MailingAddress_Country[1]": data.dig('claimant', 'address', 'countryCode'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('claimant', 'address',
                                                                                        'zipCode'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]": data.dig('claimant', 'address',
                                                                                       'zipCodeSuffix'),
            # Item 14 - Claimant Phone
            "#{base_form}.Telephone_Number_Area_Code[0]": domestic_phone_part(claimant_phone, 'areaCode'),
            "#{base_form}.Telphone_Middle_Three_Numbers[0]": domestic_phone_part(claimant_phone, 'middleThree'),
            "#{base_form}.Telephone_Last_Four_Numbers[0]": domestic_phone_part(claimant_phone, 'lastFour'),
            "#{base_form}.International_Telephone_Number_If_Applicable[1]": international_phone(claimant_phone),
            # Item 15 - Claimant Email
            "#{base_form}.E_Mail_Address_Optional[0]": data.dig('claimant', 'email')&.downcase,

            # Section III
            # Item 16A - Representative Name (split into 2 fields)
            "#{base_form}.Name_Of_Individual_Appointed_As_Representative_First_Name[0]": data.dig('representative',
                                                                                                  'firstName'),
            "#{base_form}.Last_Name[0]": data.dig('representative', 'lastName'),
            # Item 16B - Representative Type (radio button)
            "#{base_form}.RadioButtonList[0]": rep_type_radio_value(data.dig('representative', 'type'))
          }
        end

        def updated_page2_options(data) # rubocop:disable Metrics/MethodLength
          base_form = 'form1[0].#subform[1]'
          {
            # Header
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[1]": data.dig('veteran', 'ssn')[5..8],
            # Item 16C - Representative Address
            "#{base_form}.MailingAddress_NumberAndStreet[2]": data.dig('representative', 'address', 'addressLine1'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[2]": data.dig('representative', 'address',
                                                                             'addressLine2'),
            "#{base_form}.MailingAddress_City[2]": data.dig('representative', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[2]": data.dig('representative', 'address', 'stateCode'),
            "#{base_form}.MailingAddress_Country[2]": data.dig('representative', 'address', 'countryCode'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[2]": data.dig('representative', 'address',
                                                                                        'zipCode'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_LastFourNumbers[2]": data.dig('representative', 'address',
                                                                                       'zipCodeSuffix'),
            # Item 19a - Disclosure to affiliated personnel
            "#{base_form}.Checkbox_I_Authorize_VA_To_Disclose_All_My_Records_Other_Than_As_Provided_In_Items_20_And_21[0]": data['consentDisclosureAffiliated'] == true ? 1 : 0, # rubocop:disable Layout/LineLength
            "#{base_form}.Provide_The_Name_Of_The_Firm_Or_Organization_Here[0]": data['firmOrOrgName'],
            # Item 19b - Disclosure to named individuals
            "#{base_form}.Checkbox_I_Authorize_VA_To_Disclose_All_My_Records_Other_Than_As_Provided_In_Items_20_And_21[1]": data['consentDisclosureIndividuals'] == true ? 1 : 0, # rubocop:disable Layout/LineLength
            "#{base_form}.Provide_The_Names_Of_The_Individuals_Here[0]": data['individualNames']&.join(', '),
            # Item 20 - Record Consent
            "#{base_form}.AuthorizationForRepAccessToRecords[0]": data['recordConsent'] == true ? 1 : 0,
            # Item 21 - Limitation of Consent
            "#{base_form}.RelationshipToVeteran[1]": data['consentLimits']&.join(', ')&.gsub('_', ' '),
            # Item 22 - Address Change Authorization
            "#{base_form}.AuthorizationForRepActClaimantsBehalf[0]": data['consentAddressChange'] == true ? 1 : 0
          }
        end

        def updated_page3_options(data)
          base_form = 'form1[0].#subform[2]'
          appt_date = data['appointmentDate']&.to_date
          {
            # Header
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[2]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[2]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[2]": data.dig('veteran', 'ssn')[5..8],
            # Item 23B - Date Signed (Veteran/Claimant)
            "#{base_form}.Date_Signed_Month[2]": appt_date&.strftime('%m'),
            "#{base_form}.Date_Signed_Day[2]": appt_date&.strftime('%d'),
            "#{base_form}.Date_Signed_Year[2]": appt_date&.strftime('%Y'),
            # Item 24 - Limitations on Representation
            "#{base_form}.LIMITATIONS[0]": data['conditionsOfAppointment']&.join(', '),
            # Item 25B - Date Signed (Representative)
            "#{base_form}.Date_Signed_Month[3]": appt_date&.strftime('%m'),
            "#{base_form}.Date_Signed_Day[3]": appt_date&.strftime('%d'),
            "#{base_form}.Date_Signed_Year[3]": appt_date&.strftime('%Y')
          }
        end

        def legacy_page2_options(data)
          base_form = 'form1[0].#subform[1]'
          {
            # Header
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[1]": data.dig('veteran', 'ssn')[5..8],
            # Section IV
            # Item 19
            "#{base_form}.AuthorizationForRepAccessToRecords[0]": data['recordConsent'] == true ? 1 : 0,
            # Item 20
            "#{base_form}.LIMITATIONOFCONSENT[0]": data['consentLimits']&.join(', ')&.gsub('_', ' '),
            # Item 21
            "#{base_form}.AuthorizationForRepActClaimantsBehalf[0]": data['consentAddressChange'] == true ? 1 : 0,
            # Conditions of Appointment
            # Item 22B
            "#{base_form}.Date_Signed[0]": I18n.l(data['appointmentDate'].to_date, format: :va_form),
            # Item 23
            "#{base_form}.LIMITATIONS[0]": data['conditionsOfAppointment']&.join(', '),
            # Item 24B
            "#{base_form}.Date_Signed[1]": I18n.l(data['appointmentDate'].to_date, format: :va_form)
          }
        end

        def legacy_page1_options(data) # rubocop:disable Metrics/MethodLength
          base_form = 'form1[0].#subform[0]'
          {
            # Section !
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
            "#{base_form}.VeteransServiceNumber[0]": data.dig('veteran', 'serviceNumber'),
            # Item 6 Service Branch
            "#{base_form}.ARMYCheckbox1[0]": (data.dig('veteran', 'serviceBranch') == 'ARMY' ? 1 : 0),
            "#{base_form}.NAVYCheckbox2[0]": (data.dig('veteran', 'serviceBranch') == 'NAVY' ? 1 : 0),
            "#{base_form}.AIR_FORCECheckbox3[0]": (data.dig('veteran', 'serviceBranch') == 'AIR_FORCE' ? 1 : 0),
            "#{base_form}.MARINE_CORPSCheckbox4[0]": (data.dig('veteran', 'serviceBranch') == 'MARINE_CORPS' ? 1 : 0),
            "#{base_form}.COAST_GUARDCheckbox5[0]": (data.dig('veteran', 'serviceBranch') == 'COAST_GUARD' ? 1 : 0),
            "#{base_form}.SPACE_FORCECheckbox3[0]": (data.dig('veteran', 'serviceBranch') == 'SPACE_FORCE' ? 1 : 0),
            "#{base_form}.OTHER_Checkbox6[0]": (data.dig('veteran', 'serviceBranch') == 'OTHER' ? 1 : 0),
            "#{base_form}.JF15[0]": data.dig('veteran', 'serviceBranchOther'),
            # Item 7
            "#{base_form}.Veterans_MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'addressLine1'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[1]": data.dig('veteran', 'address', 'addressLine2'),
            "#{base_form}.MailingAddress_City[1]": data.dig('veteran', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[1]": data.dig('veteran', 'address', 'stateCode'),
            "#{base_form}.MailingAddress_Country[1]": data.dig('veteran', 'address', 'country'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('veteran', 'address',
                                                                                        'zipCode'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_ZIPOrPostalCode_LastFourNumbers[1]": data.dig(
              'veteran', 'address', 'zipCodeSuffix'
            ),
            # Item 8
            "#{base_form}.TelephoneNumber_IncludeAreaCode[0]": handle_country_code(data.dig('veteran', 'phone')),
            # Item 9
            "#{base_form}.EmailAddress_Optional[0]": data.dig('veteran', 'email'),

            # Section II
            # Item 10
            "#{base_form}.Claimants_First_Name[0]": data.dig('dependent', 'first_name'),
            "#{base_form}.Claimants_Last_Name[0]": data.dig('dependent', 'last_name'),
            # Item 11
            "#{base_form}.MailingAddress_NumberAndStreet[0]": data.dig('claimant', 'address', 'addressLine1'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[0]": data.dig('claimant', 'address', 'addressLine2'),
            "#{base_form}.MailingAddress_City[0]": data.dig('claimant', 'address', 'city'),
            "#{base_form}.MailingAddress_StateOrProvince[0]": data.dig('claimant', 'address', 'stateCode'),
            "#{base_form}.MailingAddress_Country[0]": data.dig('claimant', 'address', 'country'),
            "#{base_form}.MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('claimant', 'address',
                                                                                        'zipCode'),
            "#{base_form}.CurrentMailingAddress_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('address',
                                                                                              'zipCodeSuffix'),
            # Item 12
            "#{base_form}.TelephoneNumber_IncludeAreaCode[1]": handle_country_code(data.dig('claimant', 'phone')),
            # Item 13
            "#{base_form}.EmailAddress_Optional[1]": data.dig('claimant', 'email')&.downcase,
            # Item 14
            "#{base_form}.RelationshipToVeteran[0]": data.dig('claimant', 'relationship'),

            # Section III
            # Item 15A
            "#{base_form}.NAME_OF_INDIVIDUAL_APPOINTED_AS_REPRESENTATIVE[0]": "#{data.dig('representative',
                                                                                          'firstName')} #{data.dig(
                                                                                            'representative', 'lastName'
                                                                                          )}",
            # Item 15B
            "#{base_form}.Checkbox1[0]": (data.dig('representative', 'type') == 'ATTORNEY' ? 1 : 0),
            "#{base_form}.Checkbox2[0]": (data.dig('representative', 'type') == 'AGENT' ? 1 : 0),
            # Item 18
            "#{base_form}.ADDRESSOFINDIVIDUALAPPOINTEDASCLAIMANTSREPRESENTATATIVE[0]": stringify_address(
              data.dig('representative', 'address')
            )
          }
        end
        SERVICE_BRANCH_RADIO_VALUES = {
          'ARMY' => 4, 'NAVY' => 5, 'AIR_FORCE' => 6, 'MARINE_CORPS' => 7,
          'COAST_GUARD' => 8, 'SPACE_FORCE' => 9, 'NOAA' => 10, 'USPHS' => 11
        }.freeze

        REP_TYPE_RADIO_VALUES = {
          'ATTORNEY' => 4, 'AGENT' => 1
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

        private

        def fill_pdf(data)
          super
          return unless Flipper.enabled?(:lighthouse_claims_api_2122a_pdf_form_update)

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
