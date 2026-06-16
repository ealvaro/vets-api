# frozen_string_literal: true

require_relative '../section'

module Burials
  module PdfFill
    # Section VIII: Signature
    class Section8V2 < Section
      # Section configuration hash
      KEY = {
        'statementOfTruthSignature' => {
          key: 'form1[0].#subform[83].CLAIMANT_SIGNATURE[0]'
        },
        'dateSigned' => {
          key: 'form1[0].#subform[96].Date_Signed[0]'
        }
      }.freeze

      # No section expansion necessary
      def expand(_form_data); end
    end
  end
end
