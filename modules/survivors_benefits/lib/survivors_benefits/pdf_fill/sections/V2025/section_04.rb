# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      # Section 4: Marital Information
      class Section4 < Section
        KEY = {
          'validMarriage' => {
            key: 'form1[0].#subform[153].RadioButtonList[7]'
          },
          'marriageValidityExplanation' => {
            limit: 87,
            question_num: 4,
            question_suffix: 'A',
            question_label: 'Explain why the marriage is/was not valid',
            question_text: 'EXPLAIN WHY THE MARRIAGE IS/WAS NOT VALID',
            key: 'form1[0].#subform[153].Explanation[0]'
          },
          'marriedToVeteranAtTimeOfDeath' => {
            key: 'form1[0].#subform[153].RadioButtonList[11]'
          },
          'howMarriageEnded' => {
            key: 'form1[0].#subform[153].RadioButtonList[12]'
          },
          'howMarriageEndedExplanation' => {
            limit: 52,
            question_num: 4,
            question_suffix: 'C',
            question_label: 'How Marriage Ended',
            question_text: 'HOW MARRIAGE ENDED',
            key: 'form1[0].#subform[153].Explain[2]'
          },
          'marriageDates' => {
            'from' => {
              'month' => {
                key: 'form1[0].#subform[153].Date_Of_Marriage_Start_Month[0]'
              },
              'day' => {
                key: 'form1[0].#subform[153].Date_Of_Marriage_Day[0]'
              },
              'year' => {
                key: 'form1[0].#subform[153].Date_Of_Marriage_Year[0]'
              }
            },
            'to' => {
              'month' => {
                key: 'form1[0].#subform[153].Date_Of_Marriage_End_Month[0]'
              },
              'day' => {
                key: 'form1[0].#subform[153].Date_Of_Marriage_End_Day[0]'
              },
              'year' => {
                key: 'form1[0].#subform[153].Date_Of_Marriage_End_Year[0]'
              }
            }
          },
          'placeOfMarriage' => {
            limit: 52,
            question_num: 4,
            question_suffix: 'F',
            question_label: 'Place of Marriage (City/State or Country)',
            question_text: 'PLACE OF MARRIAGE (CITY/STATE OR COUNTRY)',
            key: 'form1[0].#subform[153].Place_Of_Marriage_City_State_or_Country[0]'
          },
          'placeOfMarriageTermination' => {
            limit: 52,
            question_num: 4,
            question_suffix: 'G',
            question_label: 'Place of Marriage Termination (City/State or Country)',
            question_text: 'PLACE OF MARRIAGE TERMINATION (CITY/STATE OR COUNTRY)',
            key: 'form1[0].#subform[153].Place_Of_Marriage_Termination_City_State_or_Country[0]'
          },
          'marriageType' => {
            key: 'form1[0].#subform[153].RadioButtonList[17]'
          },
          'marriageTypeExplanation' => {
            limit: 61,
            question_num: 4,
            question_suffix: 'H',
            question_label: 'Explain the type of marriage',
            question_text: 'EXPLAIN THE TYPE OF MARRIAGE',
            key: 'form1[0].#subform[153].Explain[3]'
          },
          'childWithVeteran' => {
            key: 'form1[0].#subform[153].RadioButtonList[9]'
          },
          'pregnantWithVeteran' => {
            key: 'form1[0].#subform[153].RadioButtonList[10]'
          },
          'livedContinuouslyWithVeteran' => {
            key: 'form1[0].#subform[153].RadioButtonList[13]'
          },
          'separationDueToAssignedReasons' => {
            key: 'form1[0].#subform[153].RadioButtonList[8]'
          },
          'separationExplanation' => {
            limit: 53,
            question_num: 4,
            question_suffix: 'M',
            question_label: 'Explain Separation Reason',
            question_text: 'EXPLAIN SEPARATION REASON',
            key: 'form1[0].#subform[153].Explain[1]'
          },
          'remarriedAfterVeteranDeath' => {
            key: 'form1[0].#subform[153].RadioButtonList[14]'
          },
          'remarriageDates' => {
            'from' => {
              'month' => {
                key: 'form1[0].#subform[153].Date_Of_Remarriage_Start_Month[0]'
              },
              'day' => {
                key: 'form1[0].#subform[153].Date_Of_Remarriage_Day[0]'
              },
              'year' => {
                key: 'form1[0].#subform[153].Date_Of_Remarriage_Year[0]'
              }
            },
            'to' => {
              'month' => {
                key: 'form1[0].#subform[153].Date_Of_Remarriage_End_Month[0]'
              },
              'day' => {
                key: 'form1[0].#subform[153].Date_Of_Remarriage_End_Day[0]'
              },
              'year' => {
                key: 'form1[0].#subform[153].Date_Of_Remarriage_End_Year[0]'
              }
            }
          },
          'remarriageEndCause' => {
            key: 'form1[0].#subform[153].RadioButtonList[16]'
          },
          'remarriageEndCauseExplanation' => {
            limit: 45,
            question_num: 4,
            question_suffix: 'Q',
            question_label: 'Explain Remarriage End Cause',
            question_text: 'EXPLAIN REMARRIAGE END CAUSE',
            key: 'form1[0].#subform[153].Explain[0]'
          },
          'claimantHasAdditionalMarriages' => {
            key: 'form1[0].#subform[153].RadioButtonList[15]'
          }
        }.freeze
        def expand(form_data)
          [
            method(:expand_marriage),
            method(:expand_separation),
            method(:expand_remarriage),
            method(:expand_additional_marriages)
          ].inject(form_data) { |data, func| func.call(data) }
        end

        def expand_marriage(form_data)
          form_data['validMarriage'] = to_radio_yes_no(form_data['validMarriage'])
          form_data['marriedToVeteranAtTimeOfDeath'] = to_radio_yes_no(form_data['marriedToVeteranAtTimeOfDeath'])
          form_data['howMarriageEnded'] = if form_data['marriedToVeteranAtTimeOfDeath'] == 'YES'
                                            'DEATH'
                                          else
                                            radio_marriage_ended(form_data['howMarriageEnded'])
                                          end
          form_data['marriageDates'] = {
            'from' => split_date(form_data.dig('marriageDates', 'from')),
            'to' => split_date(form_data.dig('marriageDates', 'to'))
          }
          form_data['marriageType'] = to_radio_marriage_type(form_data['marriageType'])
          form_data['childWithVeteran'] = to_radio_yes_no(form_data['childWithVeteran'])
          form_data['pregnantWithVeteran'] = to_radio_yes_no_numeric(form_data['pregnantWithVeteran'])
          form_data['livedContinuouslyWithVeteran'] = to_radio_yes_no(form_data['livedContinuouslyWithVeteran'])
          form_data
        end

        def expand_separation(form_data)
          form_data['separationDueToAssignedReasons'] =
            to_radio_yes_no_numeric(form_data['separationDueToAssignedReasons'])
          form_data
        end

        def expand_remarriage(form_data)
          # remarriedAfterVeteralDeath is from v2022,
          # but needs to be fixed on the frontend before we can remove from here.
          remarried_after_veteran_death = if form_data.key?('remarriedAfterVeteralDeath')
                                            form_data['remarriedAfterVeteralDeath']
                                          else
                                            form_data['remarriedAfterVeteranDeath']
                                          end
          form_data['remarriedAfterVeteranDeath'] = to_radio_yes_no_numeric(remarried_after_veteran_death)
          form_data['remarriageDates'] = {
            'from' => split_date(form_data.dig('remarriageDates', 'from')),
            'to' => split_date(form_data.dig('remarriageDates', 'to'))
          }
          form_data['remarriageEndCause'] = radio_remarriage_ended(form_data['remarriageEndCause'])
          form_data
        end

        def expand_additional_marriages(form_data)
          form_data['claimantHasAdditionalMarriages'] = to_radio_yes_no(form_data['claimantHasAdditionalMarriages'])
          form_data
        end

        def to_radio_yes_no(obj)
          case obj
          when true then 'YES'
          when false then 'NO'
          else 'Off'
          end
        end

        def to_radio_yes_no_numeric(obj)
          case obj
          when true then 1
          when false then 2
          else 'Off'
          end
        end

        def radio_marriage_ended(how_marriage_ended)
          case how_marriage_ended
          when 'death' then 'DEATH'
          when 'divorce' then 'DIVORCE'
          when 'other' then 'OTHER (Explain)'
          else 'Off'
          end
        end

        def to_radio_marriage_type(marriage_type)
          case marriage_type
          when 'ceremonial' then 'CEREMONIAL'
          when 'other' then 'OTHER (Explain):'
          else 'Off'
          end
        end

        def radio_remarriage_ended(how_remarriage_ended)
          case how_remarriage_ended
          when 'death' then '4'
          when 'divorce' then '1'
          when 'didNotEnd' then '3'
          when 'other' then '2'
          else 'Off'
          end
        end
      end
    end
  end
end
