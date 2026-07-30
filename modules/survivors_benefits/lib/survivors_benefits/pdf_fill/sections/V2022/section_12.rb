# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    # Section XII: Claim Certification And Signature
    class Section12 < Section
      KEY = {
        'p18HeaderVeteranSocialSecurityNumber' => {
          'first' => {
            key: 'form1[0].#subform[218].VeteransSocialSecurityNumber_FirstThreeNumbers[8]'
          },
          'second' => {
            key: 'form1[0].#subform[218].VeteransSocialSecurityNumber_SecondTwoNumbers[8]'
          },
          'third' => {
            key: 'form1[0].#subform[218].VeteransSocialSecurityNumber_LastFourNumbers[8]'
          }
        },
        'dateSigned' => {
          'month' => {
            key: 'form1[0].#subform[218].Date_Signed_Month[1]'
          },
          'day' => {
            key: 'form1[0].#subform[218].Date_Signed_Day[1]'
          },
          'year' => {
            key: 'form1[0].#subform[218].Date_Signed_Year[1]'
          }
        },
        'dateSignedAlt' => {
          'month' => {
            key: 'form1[0].#subform[218].Date_Signed_Month[0]'
          },
          'day' => {
            key: 'form1[0].#subform[218].Date_Signed_Day[0]'
          },
          'year' => {
            key: 'form1[0].#subform[218].Date_Signed_Year[0]'
          }
        }
      }.freeze

      def expand(form_data = {})
        form_data['p18HeaderVeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])
        date_signed = split_date(
          form_data['dateSigned'] || Time.zone.today.strftime('%Y-%m-%d')
        )

        if custodian_filing?(form_data['claimantRelationship'])
          form_data.delete('dateSigned')
          form_data['dateSignedAlt'] = date_signed
        else
          form_data.delete('dateSignedAlt')
          form_data['dateSigned'] = date_signed
        end
        form_data
      end
    end
  end
end
