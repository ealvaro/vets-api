# frozen_string_literal: true

require 'increase_compensation/pdf_fill/section'

module IncreaseCompensation
  module PdfFill
    # Section VI: AUTHORIZATION, CERTIFICATION, AND SIGNATURE
    class Section6 < Section
      # Section configuration hash
      KEY = {
        'signature' => {
          key: 'form1[0].#subform[4].SignatureField11[0]'
        },
        'signatureDate' => {
          'month' => {
            key: 'form1[0].#subform[4].DATESOFEMPLOYMENT5_FROM_MONTH[1]'
          },
          'day' => {
            key: 'form1[0].#subform[4].DATESOFEMPLOYMENT5_FROM_DAY[1]'
          },
          'year' => {
            key: 'form1[0].#subform[4].DATESOFEMPLOYMENT5_FROM_YEAR[1]'
          }
        },
        'witnessSignature1' => {
          'signature' => {
            limit: 38,
            question_number: 29,
            question_suffix: 'A',
            question_label: 'Signature of Witness 1',
            question_text: 'Signature of Witness 1',
            key: 'form1[0].#subform[4].Signature[0]'
          },
          'address1' => {
            key: 'form1[0].#subform[4].ADDRESS_OF_WITNESS[0]',
            limit: 17,
            question_num: 29,
            question_suffix: 'B',
            question_text: 'Address of Witness 1'
          },
          'address2' => { key: 'form1[0].#subform[4].ADDRESS_OF_WITNESS[1]' }
        },
        'witnessSignature2' => {
          'signature' => {
            limit: 38,
            question_number: 30,
            question_suffix: 'A',
            question_label: 'Signature of Witness 2',
            question_text: 'Signature of Witness 2',
            key: 'form1[0].#subform[4].Signature[1]'
          },
          'address1' => {
            key: 'form1[0].#subform[4].ADDRESS_OF_WITNESS[2]',
            limit: 17,
            question_num: 30,
            question_suffix: 'B',
            question_text: 'Address of Witness 2'
          },
          'address2' => { key: 'form1[0].#subform[4].ADDRESS_OF_WITNESS[3]' }
        }
      }.freeze
      def expand(form_data = {})
        form_data['signatureDate'] = split_date(
          form_data['signatureDate'].presence ||
          Date.current.in_time_zone('America/Chicago').strftime('%Y-%m-%d')
        )
        form_data['signature'] = form_data['signature'] || veteran_full_name(form_data)
        form_data['witnessSignature1'] = handle_witnesses(form_data, 'witnessSignature1')
        form_data['witnessSignature2'] = handle_witnesses(form_data, 'witnessSignature2')
      end

      def veteran_full_name(form_data)
        "#{form_data['veteranFullName']['first']} #{form_data['veteranFullName']['last']}"
      end

      def handle_witnesses(form_data, witness_key)
        witness = form_data[witness_key]
        return {} if witness.nil?

        if witness['address'].length > 34
          witness['address1'] = witness['address']
        else
          witness.merge!(
            two_line_overflow(witness['address'], 'address', 17)
          )
        end
        witness
      end
    end
  end
end
