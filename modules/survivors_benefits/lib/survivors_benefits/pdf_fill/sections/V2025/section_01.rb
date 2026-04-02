# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      # Section I: Veteran's Identification Information
      class Section1 < Section
        KEY = {
          # 1A
          'veteranFullName' => {
            'first' => {
              limit: 12,
              question_num: 1,
              question_suffix: 'A',
              question_label: "Veteran's First Name",
              question_text: 'VETERAN\'S FIRST NAME',
              key: 'form1[0].#subform[152].VeteransFirstName[0]'
            },
            'middle' => {
              limit: 1,
              question_num: 1,
              question_suffix: 'A',
              key: 'form1[0].#subform[152].VeteransMiddleInitial1[0]'
            },
            'last' => {
              limit: 18,
              question_num: 1,
              question_suffix: 'A',
              question_label: "Veteran's Last Name",
              question_text: 'VETERAN\'S LAST NAME',
              key: 'form1[0].#subform[152].VeteransLastName[0]'
            }
          },
          # 1B
          'section1VeteranSocialSecurityNumber' => {
            'first' => {
              key: 'form1[0].#subform[152].VeteransSocialSecurityNumber_FirstThreeNumbers[0]'
            },
            'second' => {
              key: 'form1[0].#subform[152].VeteransSocialSecurityNumber_SecondTwoNumbers[0]'
            },
            'third' => {
              key: 'form1[0].#subform[152].VeteransSocialSecurityNumber_LastFourNumbers[0]'
            }
          },
          # 1C
          'veteranDateOfBirth' => {
            'month' => {
              key: 'form1[0].#subform[152].DOBmonth[0]'
            },
            'day' => {
              key: 'form1[0].#subform[152].DOBday[0]'
            },
            'year' => {
              key: 'form1[0].#subform[152].DOByear[0]'
            }
          },
          # 1D
          'vaClaimsHistory' => {
            key: 'form1[0].#subform[152].RadioButtonList[0]'
          },
          # 1E
          'vaFileNumber' => {
            question_num: 1,
            question_suffix: 'C',
            key: 'form1[0].#subform[152].VAFileNumber[0]'
          },
          # 1F
          'diedOnDuty' => {
            key: 'form1[0].#subform[152].RadioButtonList[1]'
          },
          # 1G
          'veteranServiceNumber' => {
            key: 'form1[0].#subform[152].VETERANS_SERVICE_NUMBER[0]'
          },
          # 1H
          'veteranDateOfDeath' => {
            'month' => {
              key: 'form1[0].#subform[152].DATE_OF_DEATH_Month[0]'
            },
            'day' => {
              key: 'form1[0].#subform[152].DATE_OF_DEATH_Day[0]'
            },
            'year' => {
              key: 'form1[0].#subform[152].DATE_OF_DEATH_Year[0]'
            }
          }
        }.freeze
        def expand(form_data = {})
          veteran_full_name = form_data['veteranFullName'] ||= {}
          veteran_full_name['first'] = veteran_full_name['first']&.titleize
          veteran_full_name['middle'] = veteran_full_name['middle']&.first&.titleize
          veteran_full_name['last'] = veteran_full_name['last']&.titleize
          form_data['section1VeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])
          form_data['veteranDateOfBirth'] = split_date(form_data['veteranDateOfBirth'])
          form_data['vaClaimsHistory'] = to_radio_yes_no(form_data['vaClaimsHistory'])
          form_data['diedOnDuty'] = to_radio_yes_no(form_data['diedOnDuty'])
          form_data['veteranDateOfDeath'] = split_date(form_data['veteranDateOfDeath'])
          form_data
        end

        ##
        # Converts a boolean-like value into a radio button label.
        #
        # @param obj [Boolean, nil] the value to convert
        # @return [String] 'YES', 'NO', or 'Off'
        #
        def to_radio_yes_no(obj)
          case obj
          when true then 'YES'
          when false then 'NO'
          else 'Off'
          end
        end
      end
    end
  end
end
