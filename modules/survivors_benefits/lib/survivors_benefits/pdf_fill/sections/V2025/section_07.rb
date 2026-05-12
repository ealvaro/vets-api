# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      # Section 7: Dependency and Indemnity Compensation (D.I.C.)
      class Section7 < Section
        KEY = {
          'p14HeaderVeteranSocialSecurityNumber' => {
            'first' => {
              key: 'form1[0].#subform[156].VeteransSocialSecurityNumber_FirstThreeNumbers[4]'
            },
            'second' => {
              key: 'form1[0].#subform[156].VeteransSocialSecurityNumber_SecondTwoNumbers[4]'
            },
            'third' => {
              key: 'form1[0].#subform[156].VeteransSocialSecurityNumber_LastFourNumbers[4]'
            }
          },
          'benefit' => {
            key: 'form1[0].#subform[156].RadioButtonList[28]'
          },
          'treatmentFacilityOne' => {
            'facilityName' => {
              limit: 40,
              question_num: 7,
              question_suffix: 'B',
              question_label: 'Name Of VA Medical Center 1',
              question_text: 'NAME OF VA MEDICAL CENTER 1',
              key: 'form1[0].#subform[156].Name_And_Location_Of_VA_Medical_Center[0]'
            },
            'facilityLocation' => {
              limit: 20,
              question_num: 7,
              question_suffix: 'B',
              question_label: 'Location Of VA Medical Center 1',
              question_text: 'LOCATION OF VA MEDICAL CENTER 1',
              key: 'form1[0].#subform[156].Name_And_Location_Of_VA_Medical_Center[3]'
            },
            'startDate' => {
              'month' => {
                key: 'form1[0].#subform[156].Date_Month[11]'
              },
              'day' => {
                key: 'form1[0].#subform[156].Date_Day[11]'
              },
              'year' => {
                key: 'form1[0].#subform[156].Date_Year[11]'
              }
            },
            'endDate' => {
              'month' => {
                key: 'form1[0].#subform[156].Date_Month[14]'
              },
              'day' => {
                key: 'form1[0].#subform[156].Date_Day[14]'
              },
              'year' => {
                key: 'form1[0].#subform[156].Date_Year[14]'
              }
            }
          },
          'treatmentFacilityTwo' => {
            'facilityName' => {
              limit: 40,
              question_num: 7,
              question_suffix: 'B',
              question_label: 'Name Of VA Medical Center 2',
              question_text: 'NAME OF VA MEDICAL CENTER 2',
              key: 'form1[0].#subform[156].Name_And_Location_Of_VA_Medical_Center[1]'
            },
            'facilityLocation' => {
              limit: 20,
              question_num: 7,
              question_suffix: 'B',
              question_label: 'Location Of VA Medical Center 2',
              question_text: 'LOCATION OF VA MEDICAL CENTER 2',
              key: 'form1[0].#subform[156].Name_And_Location_Of_VA_Medical_Center[4]'
            },
            'startDate' => {
              'month' => {
                key: 'form1[0].#subform[156].Date_Month[12]'
              },
              'day' => {
                key: 'form1[0].#subform[156].Date_Day[12]'
              },
              'year' => {
                key: 'form1[0].#subform[156].Date_Year[12]'
              }
            },
            'endDate' => {
              'month' => {
                key: 'form1[0].#subform[156].Date_Month[15]'
              },
              'day' => {
                key: 'form1[0].#subform[156].Date_Day[15]'
              },
              'year' => {
                key: 'form1[0].#subform[156].Date_Year[15]'
              }
            }
          },
          'treatmentFacilityThree' => {
            'facilityName' => {
              limit: 40,
              question_num: 7,
              question_suffix: 'B',
              question_label: 'Name Of VA Medical Center 3',
              question_text: 'NAME OF VA MEDICAL CENTER 3',
              key: 'form1[0].#subform[156].Name_And_Location_Of_VA_Medical_Center[2]'
            },
            'facilityLocation' => {
              limit: 20,
              question_num: 7,
              question_suffix: 'B',
              question_label: 'Location Of VA Medical Center 3',
              question_text: 'LOCATION OF VA MEDICAL CENTER 3',
              key: 'form1[0].#subform[156].Name_And_Location_Of_VA_Medical_Center[5]'
            },
            'startDate' => {
              'month' => {
                key: 'form1[0].#subform[156].Date_Month[13]'
              },
              'day' => {
                key: 'form1[0].#subform[156].Date_Day[13]'
              },
              'year' => {
                key: 'form1[0].#subform[156].Date_Year[13]'
              }
            },
            'endDate' => {
              'month' => {
                key: 'form1[0].#subform[156].Date_Month[16]'
              },
              'day' => {
                key: 'form1[0].#subform[156].Date_Day[16]'
              },
              'year' => {
                key: 'form1[0].#subform[156].Date_Year[16]'
              }
            }
          }
        }.freeze

        def expand(form_data)
          form_data['p14HeaderVeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])
          form_data['benefit'] = benefit_to_radio(form_data['benefit'])
          form_data['treatments'] ||= []
          treatments = form_data['treatments'].map { |treatment| expand_treatment(treatment) }
          form_data['treatmentFacilityOne'] = treatments.first || {}
          form_data['treatmentFacilityTwo'] = treatments.second || {}
          form_data['treatmentFacilityThree'] = treatments.third || {}
          form_data
        end

        def expand_treatment(treatment = {})
          treatment.merge({
                            'facilityName' => treatment['vaMedicalCenterName'] || '',
                            'facilityLocation' => [treatment['city'].presence,
                                                   treatment['state'].presence].compact.join(', '),
                            'startDate' => split_date(treatment['startDate']),
                            'endDate' => split_date(treatment['endDate'])
                          })
        end

        # regrettably, these are not numbered in the 534ez PDF
        def benefit_to_radio(benefit)
          case benefit
          when 'DIC' then 'D.I.C.'
          when 'pactActDIC' then 'D.I.C. due to claimant election of a re-evaluation of a previously' \
                                 ' denied claim based on expanded eligibility under PL 117-168 (PACT Act) '
          when '1151DIC' then 'D.I.C. under U.S.C. 1151 (Note: D.I.C. under 38 U.S.C. is a rare benefit.)'
          else 'Off'
          end
        end
      end
    end
  end
end
