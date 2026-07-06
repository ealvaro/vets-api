# frozen_string_literal: true

require 'pdf_fill/extras_generator_v2'
require 'securerandom'

module SimpleFormsApi
  class Overflow210788
    # data => {
    #   question_6 = ""
    #   people_for = [{}]
    # ]
    # both fields are optional

    def initialize(data, cutoff:)
      @data = data || {}
      @cutoff = cutoff
    end

    # rubocop:disable Metrics/MethodLength
    def generate
      gen = PdfFill::ExtrasGeneratorV2.new(
        form_name: '21-0788',
        submit_date: nil,
        start_page: 2,
        show_jumplinks: false,
        question_key: [
          { question_number: '6',
            question_text: 'RELATIONSHIP TO VETERAN' },
          { question_number: '10',
            question_text: 'RELATIONSHIP TO VETERAN' },
          { question_number: '14',
            question_text: 'REMARKS' }
        ]
      )

      if @data['question_6'].present?
        gen.add_text(
          @data['question_6'],
          question_num: 6,
          question_suffix: '',
          question_text: 'RELATIONSHIP TO VETERAN',
          question_type: 'free_text',
          show_suffix: false
        )
      end

      if @data['people_for'].present?
        @data['people_for'].each do |p|
          gen.add_text(
            "#{p['full_name']} - #{p['other_relationship_description']}",
            question_num: 10,
            question_suffix: 'C',
            question_text: 'RELATIONSHIP TO VETERAN',
            question_type: 'free_text',
            show_suffix: true
          )
        end
      end

      if @data['remarks'].present?
        gen.add_text(
          @data['remarks'],
          question_num: 14,
          question_suffix: '',
          question_text: 'REMARKS',
          question_type: 'free_text',
          show_suffix: false
        )
      end

      gen.generate
    rescue => e
      Rails.logger.error(
        'OverflowPdfGenerator failed:', { error: e }
      )
      nil
    end
    # rubocop:enable Metrics/MethodLength
  end
end
