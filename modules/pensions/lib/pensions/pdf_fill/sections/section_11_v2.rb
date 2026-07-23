# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section XI: Direct Deposit Information
    class Section11V2 < Section
      # Section configuration hash
      KEY = {
        'bankAccount' => {
          # 11a
          'bankName' => {
            limit: 30,
            question_num: 11,
            question_suffix: 'A',
            question_label: 'Name of Financial Institution',
            question_text: 'NAME OF FINANCIAL INSTITUTION',
            key: 'bank_name'
          },
          # 11b
          'accountType' => {
            key: 'bank_account_type'
          },
          # 11c
          'routingNumber' => {
            limit: 9,
            question_num: 11,
            question_suffix: 'C',
            question_label: 'Routing Number',
            question_text: 'ROUTING NUMBER',
            key: 'routing_number'
          },
          # 11d
          'accountNumber' => {
            limit: 15,
            question_num: 11,
            question_suffix: 'D',
            question_label: 'Account Number',
            question_text: 'ACCOUNT NUMBER',
            key: 'account_number'
          }
        }
      }.freeze

      ##
      # Processes bank account information, converting account type to expected PDF values.
      #
      # @param form_data [Hash]
      #
      # @note Modifies `form_data`
      #
      def expand(form_data)
        form_data['bankAccount'] ||= {}
        account_type = form_data.dig('bankAccount', 'accountType')
        form_data['bankAccount']['accountType'] = ACCOUNT_TYPE.fetch(account_type, ACCOUNT_TYPE['none'])
      end
    end
  end
end
