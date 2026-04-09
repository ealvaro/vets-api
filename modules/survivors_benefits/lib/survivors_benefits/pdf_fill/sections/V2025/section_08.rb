# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      # Section VIII: Nursing Home or Increased Survivors Entitlement
      class Section8 < Section
        # Section configuration hash
        KEY = {
          'claimingMonthlySpecialPension' => {
            key: 'form1[0].#subform[156].RadioButtonList[27]'
          },
          'claimantLivesInANursingHomeYes' => {
            key: 'form1[0].#subform[156].CheckboxYES[0]'
          },
          'claimantLivesInANursingHomeNo' => {
            key: 'form1[0].#subform[156].CheckboxNO[0]'
          }
        }.freeze

        def expand(form_data = {})
          form_data['claimingMonthlySpecialPension'] =
            case form_data['claimingMonthlySpecialPension']
            when true then '1'
            when false then 'NO'
            else 'Off'
            end

          case form_data['claimantLivesInANursingHome']
          when true
            form_data['claimantLivesInANursingHomeYes'] = '1'
            form_data['claimantLivesInANursingHomeNo'] = 'Off'
          when false
            form_data['claimantLivesInANursingHomeYes'] = 'Off'
            form_data['claimantLivesInANursingHomeNo'] = '1'
          else
            form_data['claimantLivesInANursingHomeYes'] = 'Off'
            form_data['claimantLivesInANursingHomeNo'] = 'Off'
          end

          form_data
        end
      end
    end
  end
end
