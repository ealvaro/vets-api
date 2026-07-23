# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section IV: Pension Information
    class Section4V2 < Section
      # Section configuration hash
      KEY = {
        # 4a
        'socialSecurityDisability' => {
          key: 'social_security_disablity'
        },
        # 4b
        'medicalCondition' => {
          key: 'medical_condition'
        },
        # 4c
        'nursingHome' => {
          key: 'nursing_home'
        },
        # 4d
        'medicaidStatus' => {
          key: 'medicaid_status'
        },
        # 4e
        'specialMonthlyPension' => {
          key: 'special_monthly_pension'
        },
        # 4f
        'vaTreatmentHistory' => {
          key: 'va_treatment_history'
        },
        'vaMedicalCenters' => {
          item_label: 'VA medical center',
          limit: 1,
          first_key: 'medicalCenter',
          'medicalCenter' => {
            limit: 72,
            question_num: 4,
            question_suffix: 'F',
            question_label: 'Specify VA Facility',
            question_text: 'Specify VA Facility',
            key: 'va_medical_center'
          }
        },
        # 4g
        'federalTreatmentHistory' => {
          key: 'federal_treatment_history'
        },
        'federalMedicalCenters' => {
          item_label: 'Federal medical facility',
          limit: 1,
          first_key: 'medicalCenter',
          'medicalCenter' => {
            limit: 38,
            question_num: 4,
            question_suffix: 'G',
            question_label: 'Specify Federal Facility',
            question_text: 'Specify Federal Facility',
            key: 'federal_medical_center'
          }
        }
      }.freeze

      ##
      # Expand the form data for pension information and treatment history
      #
      # @param form_data [Hash] The form data hash
      #
      # @return [Hash] form data
      #
      # Note: This method modifies `form_data`
      #
      def expand(form_data)
        expand_pension_info(form_data)
        expand_treatment_history(form_data)
      end

      private

      ##
      # Expand the form data for pension information
      #
      # @param form_data [Hash] The form data hash
      #
      # @return [Integer]
      #
      # Note: This method modifies `form_data`
      #
      def expand_pension_info(form_data)
        form_data['socialSecurityDisability'] = to_radio_yes_no(
          form_data['socialSecurityDisability'] || form_data['isOver65']
        )
        # Skip 4B if YES to social security disability
        if yes?(form_data['socialSecurityDisability'])
          form_data.delete('medicalCondition')
        else
          form_data['medicalCondition'] =
            to_radio_yes_no(form_data['medicalCondition'])
        end

        form_data['nursingHome'] = to_radio_yes_no(form_data['nursingHome'])
        # Skip 4D if NO to nursing home
        if yes?(form_data['nursingHome'])
          form_data['medicaidStatus'] = to_radio_yes_no(
            form_data['medicaidStatus'] || form_data['medicaidCoverage']
          )
        else
          form_data.delete('medicaidStatus')
        end

        form_data['specialMonthlyPension'] = to_radio_yes_no(form_data['specialMonthlyPension'])
      end

      ##
      # Expand treatment history
      #
      # @param form_data [Hash] The form data hash
      #
      # @return [Hash]
      #
      # Note: This method modifies `form_data`
      #
      def expand_treatment_history(form_data)
        form_data.merge!(
          {
            'vaTreatmentHistory' => to_radio_yes_no(form_data['vaTreatmentHistory']),
            'federalTreatmentHistory' => to_radio_yes_no(form_data['federalTreatmentHistory'])
          }
        )
      end
    end
  end
end
