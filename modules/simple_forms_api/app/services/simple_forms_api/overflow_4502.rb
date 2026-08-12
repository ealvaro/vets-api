# frozen_string_literal: true

require 'pdf_fill/extras_generator_v2'
require 'securerandom'

module SimpleFormsApi
  class Overflow4502
    def initialize(data)
      @data = data || {}
    end

    # rubocop:disable Metrics/MethodLength
    def generate
      gen = PdfFill::ExtrasGeneratorV2.new(
        form_name: '21-4502',
        submit_date: nil,
        start_page: 5,
        show_jumplinks: false,
        question_key: [
          { question_number: '7', question_text: 'EMAIL ADDRESS' },
          { question_number: '30', question_text: 'I WILL OPERATE THIS VEHICLE' }
        ]
      )
      if @data.key?('email')
        gen.add_text(
          @data['email'],
          question_num: 7,
          question_suffix: '',
          question_text: 'EMAIL ADDRESS',
          question_type: 'free_text',
          show_suffix: false
        )
      end

      if @data.key?('veteran_will_operate_vehicle')
        gen.add_text(
          overflow_text,
          question_num: 30,
          question_suffix: 'A',
          question_text: 'I Will Operate This Vehicle',
          question_type: 'free_text',
          show_suffix: true
        )
      end

      gen.generate
    rescue => e
      Rails.logger.error(
        "OverflowPdfGenerator failed: #{e.class} at #{e.backtrace&.first}"
      )
      nil
    end
    # rubocop:enable Metrics/MethodLength

    private

    def overflow_text
      @data['veteran_will_operate_vehicle'] ? 'True, veteran may drive' : 'False, I am a passenger only'
    end
  end
end
