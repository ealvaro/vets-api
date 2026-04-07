# frozen_string_literal: true

require 'pdf_fill/extras_generator_v2'
require 'securerandom'

module SimpleFormsApi
  class OverflowPdfGenerator
    HEADER = 'VA Form 21-4138 — Overflow data from remark section'

    def initialize(data, cutoff:)
      @data = data || {}
      @cutoff = cutoff
    end

    # rubocop:disable Metrics/MethodLength
    def generate
      text = overflow_text
      return nil if text.blank?

      gen = PdfFill::ExtrasGeneratorV2.new(
        form_name: '21-4138',
        submit_date: nil,
        start_page: 1,
        show_jumplinks: false,
        question_key: [
          { question_number: '1A', question_text: 'Header' },
          { question_number: '2A', question_text: 'Name' },
          { question_number: '2B', question_text: 'Identifier' },
          { question_number: '3A', question_text: 'Remarks (continued)' }
        ]
      )

      # 1A. Header
      gen.add_text(
        HEADER,
        question_num: 1,
        question_suffix: 'A',
        question_text: 'Header',
        question_type: 'free_text',
        show_suffix: true
      )

      # 2A. Name
      gen.add_text(
        veteran_name_line,
        question_num: 2,
        question_suffix: 'A',
        question_text: 'Name',
        question_type: 'free_text',
        show_suffix: true
      )

      # 2B. Identifier
      gen.add_text(
        id_line,
        question_num: 2,
        question_suffix: 'B',
        question_text: 'Identifier',
        question_type: 'free_text',
        show_suffix: true
      )

      # 3A. Remarks (continued)
      gen.add_text(
        text,
        question_num: 3,
        question_suffix: 'A',
        question_text: 'Remarks (continued)',
        question_type: 'free_text',
        show_suffix: true
      )

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
      statement = (@data['statement'] || '').to_s
      return '' if statement.length <= @cutoff

      statement[(@cutoff + 1)..]
    end

    def veteran_name_line
      name = if veteran_is_filing?
               first  = @data['first'].to_s
               middle = @data['middle'].to_s
               last   = @data['last'].to_s
               full   = [first, middle, last].compact_blank.join(' ')
               full.present? ? { 'first' => first, 'middle' => middle, 'last' => last } : @data['full_name'] || {}
             else
               @data['veteran_full_name'].presence || {}
             end

      first  = name['first'].to_s
      middle = name['middle'].to_s
      last   = name['last'].to_s
      full   = [first, middle, last].compact_blank.join(' ')
      "Name: #{full.presence || 'Not provided'}"
    end

    def id_line
      id_data = if veteran_is_filing?
                  @data['id_number'] || {}
                else
                  @data['veteran_id_number'].presence || @data['id_number'] || {}
                end

      va_file = id_data['va_file_number'].to_s.presence
      ssn     = id_data['ssn'].to_s

      if va_file.present?
        "VA File Number: #{va_file}"
      elsif ssn.present?
        "SSN: #{format_ssn(ssn)}"
      else
        'ID: Not provided'
      end
    end

    def veteran_is_filing?
      @data['claimant_type'] == SimpleFormsApi::VBA214138::CLAIMANT_TYPE_VETERAN
    end

    def format_ssn(ssn)
      digits = ssn.gsub(/\D/, '')
      return ssn unless digits.length == 9

      "#{digits[0..2]}-#{digits[3..4]}-#{digits[5..8]}"
    end
  end
end
