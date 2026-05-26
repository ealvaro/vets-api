# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      class Section5 < Section
        KEY = {
          'p12HeaderVeteranSocialSecurityNumber' => {
            'first' => {
              key: 'form1[0].#subform[154].VeteransSocialSecurityNumber_FirstThreeNumbers[2]'
            },
            'second' => {
              key: 'form1[0].#subform[154].VeteransSocialSecurityNumber_SecondTwoNumbers[2]'
            },
            'third' => {
              key: 'form1[0].#subform[154].VeteransSocialSecurityNumber_LastFourNumbers[2]'
            }
          },
          'recognizedNoPrevious' => { key: 'form1[0].#subform[154].RadioButtonList[25]' },
          'veteranMarriageOne' => {
            first_key: 'reasonForSeparation',
            'spouseFullName' => {
              'first' => {
                limit: 12,
                question_num: 5,
                question_suffix: 'B',
                question_label: 'Spouse\'s First Name',
                question_text: 'SPOUSE\'S FIRST NAME',
                key: 'form1[0].#subform[154].FirstName[1]'
              },
              'middle' => {
                limit: 1,
                question_num: 5,
                question_suffix: 'B',
                key: 'form1[0].#subform[154].MiddleInitial1[1]'
              },
              'last' => {
                limit: 18,
                question_num: 5,
                question_suffix: 'B',
                question_label: 'Spouse\'s Last Name',
                question_text: 'SPOUSE\'S LAST NAME',
                key: 'form1[0].#subform[154].LastName[1]'
              }
            },
            'reasonForSeparation' => {
              key: 'form1[0].#subform[154].RadioButtonList[20]'
            },
            'reasonForSeparationExplanation' => {
              limit: 25,
              question_num: 5,
              question_suffix: 'C',
              question_label: 'Reason For Separation Explanation',
              question_text: 'REASON FOR SEPARATION EXPLANATION',
              key: 'form1[0].#subform[154].Explain[5]'
            },
            'dateOfMarriage' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[1]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[1]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[1]'
              }
            },
            'dateOfSeparation' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[0]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[0]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[0]'
              }
            },
            'locationOfMarriage' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'F',
              question_label: 'Place Of Marriage',
              question_text: 'PLACE OF MARRIAGE',
              key: 'form1[0].#subform[154].Place_Of_Marriage[1]'
            },
            'locationOfSeparation' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'G',
              question_label: 'Place Of Marriage Termination',
              question_text: 'PLACE OF MARRIAGE TERMINATION',
              key: 'form1[0].#subform[154].Place_Of_Marriage_Termination[1]'
            }
          },
          'veteranMarriageTwo' => {
            first_key: 'reasonForSeparation',
            'spouseFullName' => {
              'first' => {
                limit: 12,
                question_num: 5,
                question_suffix: 'H',
                question_label: 'Spouse\'s First Name',
                question_text: 'SPOUSE\'S FIRST NAME',
                key: 'form1[0].#subform[154].FirstName[0]'
              },
              'middle' => {
                limit: 1,
                question_num: 5,
                question_suffix: 'H',
                key: 'form1[0].#subform[154].MiddleInitial1[0]'
              },
              'last' => {
                limit: 18,
                question_num: 5,
                question_suffix: 'H',
                question_label: 'Spouse\'s Last Name',
                question_text: 'SPOUSE\'S LAST NAME',
                key: 'form1[0].#subform[154].LastName[0]'
              }
            },
            'reasonForSeparation' => {
              key: 'form1[0].#subform[154].RadioButtonList[19]'
            },
            'reasonForSeparationExplanation' => {
              limit: 25,
              question_num: 5,
              question_suffix: 'I',
              question_label: 'Reason For Separation Explanation',
              question_text: 'REASON FOR SEPARATION EXPLANATION',
              key: 'form1[0].#subform[154].Explain[4]'
            },
            'dateOfMarriage' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[5]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[5]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[5]'
              }
            },
            'dateOfSeparation' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[4]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[4]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[4]'
              }
            },
            'locationOfMarriage' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'L',
              question_label: 'Place Of Marriage',
              question_text: 'PLACE OF MARRIAGE',
              key: 'form1[0].#subform[154].Place_Of_Marriage[0]'
            },
            'locationOfSeparation' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'M',
              question_label: 'Place Of Marriage Termination',
              question_text: 'PLACE OF MARRIAGE TERMINATION',
              key: 'form1[0].#subform[154].Place_Of_Marriage_Termination[0]'
            }
          },
          'veteranHasAdditionalMarriages' => {
            key: 'form1[0].#subform[154].RadioButtonList[21]'
          },
          'spouseMarriageOne' => {
            first_key: 'reasonForSeparation',
            'spouseFullName' => {
              'first' => {
                limit: 12,
                question_num: 5,
                question_suffix: 'O',
                question_label: 'Spouse\'s First Name',
                question_text: 'SPOUSE\'S FIRST NAME',
                key: 'form1[0].#subform[154].FirstName[3]'
              },
              'middle' => {
                limit: 1,
                question_num: 5,
                question_suffix: 'O',
                key: 'form1[0].#subform[154].MiddleInitial1[3]'
              },
              'last' => {
                limit: 18,
                question_num: 5,
                question_suffix: 'O',
                question_label: 'Spouse\'s Last Name',
                question_text: 'SPOUSE\'S LAST NAME',
                key: 'form1[0].#subform[154].LastName[3]'
              }
            },
            'reasonForSeparation' => {
              key: 'form1[0].#subform[154].RadioButtonList[23]'
            },
            'reasonForSeparationExplanation' => {
              limit: 25,
              question_num: 5,
              question_suffix: 'P',
              question_label: 'Reason For Separation Explanation',
              question_text: 'REASON FOR SEPARATION EXPLANATION',
              key: 'form1[0].#subform[154].Explain[7]'
            },
            'dateOfMarriage' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[3]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[3]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[3]'
              }
            },
            'dateOfSeparation' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[2]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[2]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[2]'
              }
            },
            'locationOfMarriage' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'S',
              question_label: 'Place Of Marriage',
              question_text: 'PLACE OF MARRIAGE',
              key: 'form1[0].#subform[154].Place_Of_Marriage[3]'
            },
            'locationOfSeparation' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'T',
              question_label: 'Place Of Marriage Termination',
              question_text: 'PLACE OF MARRIAGE TERMINATION',
              key: 'form1[0].#subform[154].Place_Of_Marriage_Termination[3]'
            }
          },
          'spouseMarriageTwo' => {
            first_key: 'reasonForSeparation',
            'spouseFullName' => {
              'first' => {
                limit: 12,
                question_num: 5,
                question_suffix: 'U',
                question_label: 'Spouse\'s First Name',
                question_text: 'SPOUSE\'S FIRST NAME',
                key: 'form1[0].#subform[154].FirstName[2]'
              },
              'middle' => {
                limit: 1,
                question_num: 5,
                question_suffix: 'U',
                key: 'form1[0].#subform[154].MiddleInitial1[2]'
              },
              'last' => {
                limit: 18,
                question_num: 5,
                question_suffix: 'U',
                question_label: 'Spouse\'s Last Name',
                question_text: 'SPOUSE\'S LAST NAME',
                key: 'form1[0].#subform[154].LastName[2]'
              }
            },
            'reasonForSeparation' => {
              key: 'form1[0].#subform[154].RadioButtonList[22]'
            },
            'reasonForSeparationExplanation' => {
              limit: 25,
              question_num: 5,
              question_suffix: 'V',
              question_label: 'Reason For Separation Explanation',
              question_text: 'REASON FOR SEPARATION EXPLANATION',
              key: 'form1[0].#subform[154].Explain[6]'
            },
            'dateOfMarriage' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[7]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[7]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[7]'
              }
            },
            'dateOfSeparation' => {
              'month' => {
                key: 'form1[0].#subform[154].Date_Month[6]'
              },
              'day' => {
                key: 'form1[0].#subform[154].Date_Day[6]'
              },
              'year' => {
                key: 'form1[0].#subform[154].Date_Year[6]'
              }
            },
            'locationOfMarriage' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'Y',
              question_label: 'Place Of Marriage',
              question_text: 'PLACE OF MARRIAGE',
              key: 'form1[0].#subform[154].Place_Of_Marriage[2]'
            },
            'locationOfSeparation' => {
              limit: 42,
              question_num: 5,
              question_suffix: 'Z',
              question_label: 'Place Of Marriage Termination',
              question_text: 'PLACE OF MARRIAGE TERMINATION',
              key: 'form1[0].#subform[154].Place_Of_Marriage_Termination[2]'
            }
          },
          'spouseHasAdditionalMarriages' => {
            key: 'form1[0].#subform[154].RadioButtonList[24]'
          }
        }.freeze
        def expand(form_data)
          form_data['p12HeaderVeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])
          form_data['recognizedNoPrevious'] = recognized_no_previous_value(
            form_data['recognizedAsSpouse'],
            form_data['hadPreviousMarriages']
          )
          veteran_marriages = build_marital_history(form_data['veteranMarriages'], 'VETERAN')
          form_data['veteranMarriageOne'] = veteran_marriages.first || {}
          form_data['veteranMarriageTwo'] = veteran_marriages.second || {}
          spouse_marriages = build_marital_history(form_data['spouseMarriages'], 'SPOUSE')
          form_data['spouseMarriageOne'] = spouse_marriages.first || {}
          form_data['spouseMarriageTwo'] = spouse_marriages.second || {}
          form_data['veteranHasAdditionalMarriages'] =
            to_radio_value(form_data['veteranHasAdditionalMarriages'], true_value: '1', false_value: '2')
          form_data['spouseHasAdditionalMarriages'] =
            to_radio_value(form_data['spouseHasAdditionalMarriages'], true_value: '2', false_value: '1')
          form_data
        end

        def build_marital_history(marriages, marriage_for)
          return [] unless marriages.present? && %w[VETERAN SPOUSE].include?(marriage_for)

          marriages.map do |marriage|
            reason_for_separation = marriage['reasonForSeparation'].to_s
            spouse_full_name = marriage['spouseFullName']

            marriage.merge({
                             'spouseFullName' => spouse_full_name.is_a?(Hash) ? format_name(spouse_full_name) : {},
                             'dateOfMarriage' => split_date(marriage['dateOfMarriage']),
                             'dateOfSeparation' => split_date(marriage['dateOfSeparation']),
                             'reasonForSeparation' => Constants::REASONS_FOR_SEPARATION[reason_for_separation]
                           })
          end
        end

        def to_radio_value(value, true_value:, false_value:)
          case value
          when true then true_value
          when false then false_value
          else 'Off'
          end
        end

        def recognized_no_previous_value(recognized_as_spouse, had_previous_marriages)
          return 'Off' unless [recognized_as_spouse, had_previous_marriages].all? do |value|
            [true, false].include?(value)
          end

          recognized_as_spouse && !had_previous_marriages ? 'YES' : 'NO'
        end
      end
    end
  end
end
