# frozen_string_literal: true

require 'claims_api/v1/poa_pdf_constructor/base'
require 'claims_api/v1/poa_pdf_constructor/signature'

module ClaimsApi
  module V1
    module PoaPdfConstructor
      class Organization < ClaimsApi::V1::PoaPdfConstructor::Base
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
          if form_update_flag
            Rails.root.join('modules', 'claims_api', 'config', 'pdf_templates', '21-22', 'rev_10_27_2023')
          else
            Rails.root.join('modules', 'claims_api', 'config', 'pdf_templates', '21-22')
          end
        end

        def page1_signatures(_signatures)
          []
        end

        def page2_signatures(signatures)
          return [] if signatures.nil?

          if form_update_flag
            page2_signatures_revised(signatures)
          else
            page2_signatures_original(signatures)
          end
        end

        def page2_signatures_original(signatures)
          [
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['veteran'], x: 35, y: 263),
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['representative'], x: 35, y: 216)
          ]
        end

        # adding 65 pixels to the y coordinate of the signatures on page 2 for the revised form
        def page2_signatures_revised(signatures)
          [
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['veteran'], x: 35, y: 328),
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['representative'], x: 35, y: 281)
          ]
        end

        def page2_options(data)
          if form_update_flag
            page2_options_revised(data)
          else
            page2_options_original(data)
          end
        end

        def page1_options(data)
          if form_update_flag
            page1_options_revised(data)
          else
            page1_options_original(data)
          end
        end

        def form_update_flag
          return @form_update_flag unless @form_update_flag.nil?

          @form_update_flag = Flipper.enabled?(
            :lighthouse_claims_api_2122_pdf_form_update_v1
          )
        end

        # rubocop:disable Layout/LineLength
        def page2_options_original(data)
          base_form = 'F[0].Page_2[0]'
          {
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
            "#{base_form}.I_Authorize[1]": data['recordConsent'] == true ? 1 : 0,
            "#{base_form}.Drug_Abuse[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'DRUG_ABUSE'),
            "#{base_form}.Alcoholism_Or_Alcohol_Abuse[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'ALCOHOLISM'),
            "#{base_form}.Infection_With_The_Human_Immunodeficiency_Virus_HIV[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'HIV'),
            "#{base_form}.sicklecellanemia[0]": set_limitation_of_consent_check_box(data['consentLimits'], 'SICKLE_CELL'),
            "#{base_form}.I_Authorize[0]": data['consentAddressChange'] == true ? 1 : 0,
            "#{base_form}.Date_Signed[0]": I18n.l(Time.zone.now.to_date, format: :va_form),
            "#{base_form}.Date_Signed[1]": I18n.l(Time.zone.now.to_date, format: :va_form)
          }
        end

        # rubocop:disable Metrics/MethodLength
        def page1_options_original(data)
          base_form = 'F[0].Page_1[0]'
          {
            # Veteran
            "#{base_form}.VeteransLastName[0]": data.dig('veteran', 'lastName'),
            "#{base_form}.VeteransFirstName[0]": data.dig('veteran', 'firstName'),
            "#{base_form}.TelephoneNumber_IncludeAreaCode[1]": handle_country_code(data.dig('veteran', 'phone')),
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
            "#{base_form}.DOBmonth[0]": data.dig('veteran', 'birthdate').split('-').second,
            "#{base_form}.DOBday[0]": data.dig('veteran', 'birthdate').split('-').last.first(2),
            "#{base_form}.DOByear[0]": data.dig('veteran', 'birthdate').split('-').first,
            "#{base_form}.Veterans_MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'numberAndStreet'),
            "#{base_form}.MailingAddress_ApartmentOrUnitNumber[1]": data.dig('veteran', 'address', 'aptUnitNumber'),
            "#{base_form}.Claimants_MailingAddress_City[1]": data.dig('veteran', 'address', 'city'),
            "#{base_form}.Claimants_MailingAddress_StateOrProvince[1]": data.dig('veteran', 'address', 'state'),
            "#{base_form}.Claimants_MailingAddress_Country[1]": data.dig('veteran', 'address', 'country'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('veteran', 'address', 'zipFirstFive'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]": data.dig('veteran', 'address', 'zipLastFour'),

            # Claimant
            "#{base_form}.Claimants_FirstName[0]": data.dig('claimant', 'firstName'),
            "#{base_form}.Claimants_LastName[0]": data.dig('claimant', 'lastName'),
            "#{base_form}.Claimants_MiddleInitial1[0]": data.dig('claimant', 'middleInitial'),
            "#{base_form}.Claimants_MailingAddress_NumberAndStreet[0]": data.dig('claimant', 'address', 'numberAndStreet'),
            "#{base_form}.Claimants_MailingAddress_ApartmentOrUnitNumber[0]": data.dig('claimant', 'address', 'aptUnitNumber'),
            "#{base_form}.Claimants_MailingAddress_City[0]": data.dig('claimant', 'address', 'city'),
            "#{base_form}.Claimants_MailingAddress_StateOrProvince[0]": data.dig('claimant', 'address', 'state'),
            "#{base_form}.Claimants_MailingAddress_Country[0]": data.dig('claimant', 'address', 'country'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('claimant', 'address', 'zipFirstFive'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('address', 'zipLastFour'),
            "#{base_form}.TelephoneNumber_IncludeAreaCode[0]": handle_country_code(data.dig('claimant', 'phone')),
            "#{base_form}.Claimants_EmailAddress_Optional[0]": data.dig('claimant', 'email'),
            "#{base_form}.Relationship_To_Veteran[0]": data.dig('claimant', 'relationship'),

            "#{base_form}.Name_Of_Service_Organization[0]": data.dig('serviceOrganization', 'organizationName'),
            "#{base_form}.Name_Of_Official_Representative[0]": "#{data.dig('serviceOrganization', 'firstName')} #{data.dig('serviceOrganization', 'lastName')}",
            "#{base_form}.Email_Address[0]": data.dig('serviceOrganization', 'email'),
            "#{base_form}.Job_Title_Of_Person_Named_In_Item15A[0]": data.dig('serviceOrganization', 'jobTitle'),
            "#{base_form}.Date_Of_This_Appointment[0]": I18n.l(Time.zone.now.to_date, format: :va_form)
          }
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Layout/LineLength

        # rubocop:disable Layout/LineLength
        def page1_options_revised(data)
          page1_veteran_section(data)
            .merge(page1_claimant_section(data))
            .merge(page1_service_organization_section(data))
        end

        def page1_veteran_section(data)
          base_form = 'form1[0].#subform[0]'
          {
            # SECTION I: VETERAN'S INFORMATION
            # 1. Veteran's Name
            "#{base_form}.VeteransLastName[0]": data.dig('veteran', 'lastName'),
            "#{base_form}.VeteransFirstName[0]": data.dig('veteran', 'firstName'),
            # 2. VETERAN'S SOCIAL SECURITY NUMBER
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[0]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[0]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[0]": data.dig('veteran', 'ssn')[5..8],
            # 4. VETERAN'S DATE OF BIRTH (MM/DD/YYYY)
            "#{base_form}.DOBmonth[0]": data.dig('veteran', 'birthdate')&.split('-')&.second,
            "#{base_form}.DOBday[0]": data.dig('veteran', 'birthdate')&.split('-')&.last&.first(2),
            "#{base_form}.DOByear[0]": data.dig('veteran', 'birthdate')&.split('-')&.first,
            # 7. VETERAN'S MAILING ADDRESS (Number and Street or Rural Route)
            "#{base_form}.Claimants_MailingAddress_NumberAndStreet[0]": data.dig('veteran', 'address', 'numberAndStreet'),
            "#{base_form}.Claimants_MailingAddress_ApartmentOrUnitNumber[0]": data.dig('veteran', 'address', 'aptUnitNumber'),
            "#{base_form}.Claimants_MailingAddress_City[0]": data.dig('veteran', 'address', 'city'),
            "#{base_form}.Claimants_MailingAddress_StateOrProvince[0]": data.dig('veteran', 'address', 'state'),
            "#{base_form}.Claimants_MailingAddress_Country[0]": data.dig('veteran', 'address', 'country'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[0]": data.dig('veteran', 'address', 'zipFirstFive'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[0]": data.dig('veteran', 'address', 'zipLastFour'),
            # 8. TELEPHONE NUMBER (Include Area Code)
            "#{base_form}.Phone[0]": handle_country_code(data.dig('veteran', 'phone')),
            # 9. EMAIL ADDRESS (Optional)
            "#{base_form}.EmailAddress_Optional[0]": data.dig('veteran', 'email')
          }
        end

        def page1_claimant_section(data)
          base_form = 'form1[0].#subform[0]'
          {
            # SECTION II: CLAIMANT'S INFORMATION
            # 10. CLAIMANT'S NAME
            "#{base_form}.Claimants_FirstName[0]": data.dig('claimant', 'firstName'),
            "#{base_form}.Claimants_LastName[0]": data.dig('claimant', 'lastName'),
            "#{base_form}.Claimants_MiddleInitial1[0]": data.dig('claimant', 'middleInitial'),
            # 11A. CLAIMANT'S DATE OF BIRTH (MM/DD/YYYY) (new in revised form)
            "#{base_form}.DOBmonth[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.second,
            "#{base_form}.DOBday[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.last&.first(2),
            "#{base_form}.DOByear[1]": data.dig('claimant', 'dateOfBirth')&.split('-')&.first,
            # 11B. RELATIONSHIP TO VETERAN
            "#{base_form}.Relationship_To_Veteran[0]": data.dig('claimant', 'relationship'),
            # 12. CLAIMANT'S MAILING ADDRESS (Number and Street or Rural Route)
            "#{base_form}.Claimants_MailingAddress_NumberAndStreet[1]": data.dig('claimant', 'address', 'numberAndStreet'),
            "#{base_form}.Claimants_MailingAddress_ApartmentOrUnitNumber[1]": data.dig('claimant', 'address', 'aptUnitNumber'),
            "#{base_form}.Claimants_MailingAddress_City[1]": data.dig('claimant', 'address', 'city'),
            "#{base_form}.Claimants_MailingAddress_StateOrProvince[1]": data.dig('claimant', 'address', 'state'),
            "#{base_form}.Claimants_MailingAddress_Country[1]": data.dig('claimant', 'address', 'country'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_FirstFiveNumbers[1]": data.dig('claimant', 'address', 'zipFirstFive'),
            "#{base_form}.Claimants_MailingAddress_ZIPOrPostalCode_LastFourNumbers[1]": data.dig('claimant', 'address', 'zipLastFour'),
            # 13. TELEPHONE NUMBER (Include Area Code)
            "#{base_form}.Phone[1]": handle_country_code(data.dig('claimant', 'phone')),
            # 14. EMAIL ADDRESS (Optional)
            "#{base_form}.EmailAddress_Optional[1]": data.dig('claimant', 'email')
          }
        end

        def page1_service_organization_section(data)
          base_form = 'form1[0].#subform[0]'
          # building the rep name to avoid edge cases with missing names using string interpolation (just in case)
          rep_first_name = data.dig('serviceOrganization', 'firstName')
          rep_last_name = data.dig('serviceOrganization', 'lastName')
          rep_name = [rep_first_name, rep_last_name].filter_map(&:presence).join(' ')
          {
            # SECTION III: SERVICE ORGANIZATION INFORMATION
            # 15. NAME OF SERVICE ORGANIZATION
            "#{base_form}.Name_Of_Service_Organization[0]": data.dig('serviceOrganization', 'organizationName'),
            # 16A. NAME OF OFFICIAL REPRESENTATIVE
            "#{base_form}.Name_Of_Official_Representative[0]": rep_name,
            # 16B. JOB TITLE OF OFFICIAL REPRESENTATIVE
            "#{base_form}.Job_Title_Of_Person_Named_In_Item15A[0]": data.dig('serviceOrganization', 'jobTitle'),
            # 17. EMAIL ADDRESS OF THE ORGANIZATION IN ITEM 15
            "#{base_form}.Email_Address[0]": data.dig('serviceOrganization', 'email'),
            # 18. DATE OF THIS APPOINTMENT (MM/DD/YYYY)
            "#{base_form}.DateAppt[0]": I18n.l(Time.zone.now.to_date, format: :va_form)
          }
        end
        # rubocop:enable Layout/LineLength

        def page2_options_revised(data)
          page2_header_section(data)
            .merge(page2_authorization_section(data))
            .merge(page2_signatures_section)
        end

        def page2_header_section(data)
          base_form = 'form1[0].#subform[1]'
          {
            # HEADER
            "#{base_form}.SocialSecurityNumber_FirstThreeNumbers[1]": data.dig('veteran', 'ssn')[0..2],
            "#{base_form}.SocialSecurityNumber_SecondTwoNumbers[1]": data.dig('veteran', 'ssn')[3..4],
            "#{base_form}.SocialSecurityNumber_LastFourNumbers[1]": data.dig('veteran', 'ssn')[5..8]
          }
        end

        def page2_authorization_section(data)
          base_form = 'form1[0].#subform[1]'
          # unpack consent_limits to avoid reek of DuplicateMethodCall in the hash below
          consent_limits = data['consentLimits'] || []
          {
            # SECTION IV: AUTHORIZATION INFORMATION
            # 19. AUTHORIZATION FOR REPRESENTATIVE'S ACCESS TO RECORDS
            "#{base_form}.I_Authorize[0]": data['recordConsent'] == true ? 1 : 0,
            # 20. LIMITATION OF CONSENT
            "#{base_form}.Drug_Abuse[0]": set_limitation_of_consent_check_box(consent_limits, 'DRUG_ABUSE'),
            "#{base_form}.Alcoholism_Or_Alcohol_Abuse[0]": set_limitation_of_consent_check_box(
              consent_limits, 'ALCOHOLISM'
            ),
            "#{base_form}.Infection_With_The_Human_Immunodeficiency_Virus_HIV[0]": set_limitation_of_consent_check_box(
              consent_limits, 'HIV'
            ),
            "#{base_form}.sicklecellanemia[0]": set_limitation_of_consent_check_box(
              consent_limits, 'SICKLE_CELL'
            ),
            # 21. AUTHORIZATION FOR CHANGE OF ADDRESS
            "#{base_form}.I_Authorize[1]": data['consentAddressChange'] == true ? 1 : 0
          }
        end

        def page2_signatures_section
          base_form = 'form1[0].#subform[1]'
          {
            # SECTION V: SIGNATURES
            # 22B. DATE SIGNED (MM/DD/YYYY) (VETERAN/CLAIMANT)
            "#{base_form}.DateSigned[0]": I18n.l(Time.zone.now.to_date, format: :va_form),
            # 23B. DATE SIGNED (MM/DD/YYYY) (REPRESENTATIVE)
            "#{base_form}.DateSigned[1]": I18n.l(Time.zone.now.to_date, format: :va_form)
          }
        end
      end
    end
  end
end
