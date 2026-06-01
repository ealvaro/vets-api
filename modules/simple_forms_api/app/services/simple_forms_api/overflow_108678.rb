# frozen_string_literal: true

require 'pdf_fill/extras_generator_v2'
require 'securerandom'

module SimpleFormsApi
  class Overflow108678
    # data => [{
    #   deviceOrMedication: String,
    #   serviceConnectedDisability: String,
    #   impactedLocations: {},
    #   both: true/false or absent
    # }]

    def initialize(data, cutoff:)
      @data = data || []
      @cutoff = cutoff
    end

    # rubocop:disable Metrics/MethodLength
    def generate
      gen = PdfFill::ExtrasGeneratorV2.new(
        form_name: '10-8678',
        submit_date: nil,
        start_page: 1,
        show_jumplinks: false,
        question_key: [
          { question_number: '7',
            question_text: 'DEVICE, ORTHOPEDIC APPLIANCE OR SKIN MEDICATION IMPACTS WHICH AREA OF THE BODY' }
        ]
      )
      @data.each do |device|
        gen.add_text(
          overflow_text(device, device['both']),
          question_num: 7,
          question_suffix: 'a',
          question_text: 'DEVICE, ORTHOPEDIC APPLIANCE OR SKIN MEDICATION IMPACTS WHICH AREA OF THE BODY',
          question_type: 'free_text',
          show_suffix: false
        )
      end

      gen.generate
    rescue => e
      Rails.logger.error(
        "OverflowPdfGenerator failed: #{e.class} at #{e.backtrace&.first}"
      )
      nil
    end

    private

    def overflow_text(device, both)
      if both
        "#{device['device_or_medication']} is needed for Upper and Lower, Left and Right sides
          Issuing Facility: #{device['issuing_facility']}
        "
      else
        "#{device['device_or_medication']} is needed for both Left and Right sides
          Issuing Facility: #{device['issuing_facility']}
        "
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end
