# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section XII: Claim Certification and Signature
    class Section12V2 < Section
      # Section configuration hash
      KEY = {
        # 12a
        'statementOfTruthSignature' => {
          limit: 43,
          question_num: 12,
          question_suffix: 'A',
          question_label: 'Signature',
          question_text: 'SIGNATURE',
          key: 'statement_of_truth_signature'

        },
        # 12c
        'signatureDate' => {
          'month' => {
            key: 'date_signed_month'
          },
          'day' => {
            key: 'date_signed_day'
          },
          'year' => {
            key: 'date_signed_year'
          }
        }
      }.freeze

      ##
      # Splits the signature date into its components.
      #
      # @param form_data [Hash]
      #
      # @note Modifies `form_data`
      #
      def expand(form_data)
        signature_date = form_data['signatureDate'] || Time.zone.now.strftime('%Y-%m-%d')
        form_data['signatureDate'] = split_date(signature_date)
      end
    end
  end
end
