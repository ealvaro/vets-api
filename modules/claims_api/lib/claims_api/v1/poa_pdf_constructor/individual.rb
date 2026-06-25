# frozen_string_literal: true

require 'claims_api/v1/poa_pdf_constructor/base'
require 'claims_api/v1/poa_pdf_constructor/signature'

module ClaimsApi
  module V1
    module PoaPdfConstructor
      class Individual < ClaimsApi::V1::PoaPdfConstructor::Base
        protected

        def page_template_base_path
          path = Rails.root.join('modules', 'claims_api', 'config', 'pdf_templates', '21-22A')
          Flipper.enabled?(:lighthouse_claims_api_v1_2122a_pdf_form_update) ? path.join('rev_07_2023') : path
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
          if Flipper.enabled?(:lighthouse_claims_api_v1_2122a_pdf_form_update)
            return updated_page1_signatures(signatures)
          end

          legacy_page1_signatures(signatures)
        end

        def updated_page1_signatures(_signatures)
          [] # TODO: Update signature positions for rev_07_2023
        end

        def legacy_page1_signatures(signatures)
          [
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['veteran'], x: 35, y: 90),
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['representative'], x: 35, y: 118)
          ]
        end

        def page2_signatures(signatures)
          if Flipper.enabled?(:lighthouse_claims_api_v1_2122a_pdf_form_update)
            return updated_page2_signatures(signatures)
          end

          legacy_page2_signatures(signatures)
        end

        def updated_page2_signatures(_signatures)
          [] # TODO: Update signature positions for rev_07_2023
        end

        def legacy_page2_signatures(signatures)
          [
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['veteran'], x: 35, y: 322),
            ClaimsApi::V1::PoaPdfConstructor::Signature.new(data: signatures['representative'], x: 35, y: 216)
          ]
        end

        def page2_options(data)
          return updated_page2_options(data) if Flipper.enabled?(:lighthouse_claims_api_v1_2122a_pdf_form_update)

          legacy_page2_options(data)
        end

        def updated_page2_options(_data)
          {} # TODO: Add new form field mappings for rev_07_2023 page 2
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
          return updated_page3_options(data) if Flipper.enabled?(:lighthouse_claims_api_v1_2122a_pdf_form_update)

          {} # legacy form has no page 3 fields
        end

        def updated_page3_options(_data)
          {} # TODO: Add new form field mappings for rev_07_2023 page 3
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Layout/LineLength
        def page1_options(data)
          return updated_page1_options(data) if Flipper.enabled?(:lighthouse_claims_api_v1_2122a_pdf_form_update)

          legacy_page1_options(data)
        end

        def updated_page1_options(_data)
          {} # TODO: Add new form field mappings for rev_07_2023 page 1
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

        #
        # Converts segmented address information into single string representation.
        #
        # @param address [Hash] Segmented data representing an address
        #
        # @return [String] Single string representation of provided address
        def stringify_address(address)
          return if address.nil?

          "#{address['numberAndStreet']}, #{address['city']} #{address['state']} #{address['zipFirstFive']}"
        end
      end
    end
  end
end
