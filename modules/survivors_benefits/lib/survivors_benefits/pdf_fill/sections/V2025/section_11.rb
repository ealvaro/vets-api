# frozen_string_literal: true

require 'survivors_benefits/pdf_fill/section'

module SurvivorsBenefits
  module PdfFill
    module V2025
      # Section XI: Direct Deposit Information
      class Section11 < Section
        KEY = {
          'p17HeaderVeteranSocialSecurityNumber' => {
            'first' => {
              key: 'form1[0].#subform[162].VeteransSocialSecurityNumber_FirstThreeNumbers[7]'
            },
            'second' => {
              key: 'form1[0].#subform[162].VeteransSocialSecurityNumber_SecondTwoNumbers[7]'
            },
            'third' => {
              key: 'form1[0].#subform[162].VeteransSocialSecurityNumber_LastFourNumbers[7]'
            }
          },
          'bankAccount' => {
            'bankName' => {
              'line_one' => {
                limit: 17,
                question_num: 11,
                question_suffix: 'A',
                question_label: 'Name of Financial Institution - Line 1',
                question_text: 'NAME OF FINANCIAL INSTITUTION - LINE 1',
                key: 'form1[0].#subform[162].Name_Of_Financial_Institution[0]'
              },
              'line_two' => {
                limit: 17,
                question_num: 11,
                question_suffix: 'A',
                question_label: 'Name of Financial Institution - Line 2',
                question_text: 'NAME OF FINANCIAL INSTITUTION - LINE 2',
                key: 'form1[0].#subform[162].Name_Of_Financial_Institution[1]'
              }
            },
            'savings' => {
              question_num: 11,
              question_suffix: 'C',
              question_text: '11C. SAVINGS.',
              key: 'form1[0].#subform[162].#field[461]'
            },
            'checking' => {
              question_num: 11,
              question_suffix: 'C',
              question_text: '11C. CHECKING.',
              key: 'form1[0].#subform[162].#field[463]'
            },
            'noAccount' => {
              question_num: 11,
              question_suffix: 'C',
              # I CERTIFY THAT I DO NOT HAVE AN ACCOUNT WITH A FINANCIAL INSTITUTION OR CERTIFIED PAYMENT AGENT.
              question_text: '11C. NO ACCOUNT.',
              key: 'form1[0].#subform[162].#field[462]'
            },
            'routingNumber' => {
              limit: 9,
              key: 'form1[0].#subform[162].Routing_Or_Transit_Number[5]'
            },
            'accountNumber' => {
              limit: 10,
              question_num: 11,
              question_suffix: 'C',
              question_label: 'Account Number',
              question_text: 'ACCOUNT NUMBER',
              key: 'form1[0].#subform[162].Account_Number[5]'
            }
          }
        }.freeze
        def expand(form_data = {})
          form_data['p17HeaderVeteranSocialSecurityNumber'] = split_ssn(form_data['veteranSocialSecurityNumber'])

          account = form_data['bankAccount'] || {}
          account['bankName'] = split_bank_name(account['bankName'])
          account['savings'] = account['accountType'] == 'SAVINGS' ? '1' : 'Off'
          account['checking'] = account['accountType'] == 'CHECKING' ? '1' : 'Off'
          account['noAccount'] = account['accountType'] == 'NO_ACCOUNT' ? '1' : 'Off'
          account['routingNumber'] = digits_only(account['routingNumber'])
          account['accountNumber'] = digits_only(account['accountNumber'])
          form_data['bankAccount'] = account
          form_data
        end

        private

        def split_bank_name(bank_name)
          return bank_name if bank_name.is_a?(Hash)
          return {} if bank_name.blank?

          bank_name_str = bank_name.to_s
          chunks = bank_name_str.scan(/.{1,17}/)
          {
            'line_one' => chunks[0],
            'line_two' => bank_name_str[17..]
          }.compact
        end

        def digits_only(value)
          value.to_s.gsub(/\D/, '')
        end
      end
    end
  end
end
