# frozen_string_literal: true

require 'fileutils'

module PdfFill
  module Processors
    class VA220976Processor
      extend Forwardable

      def_delegators :@main_form_filler, :combine_extras

      PDF_FORMS = PdfForms.new(Settings.binaries.pdftk)
      DEFAULT_TEMPLATE_PATH = 'lib/pdf_fill/forms/pdfs/22-0976.pdf'
      DEFAULT_PROGRAMS_LIMIT = 4
      DEFAULT_BRANCHES_LIMIT = 4
      DEFAULT_FACULTY_LIMIT = 7
      # The entryRequirements field on the pdf is small, so any program whose text is
      # longer than this is extracted in full to the overflow page, leaving only
      # 'See Additional Page' in that program's Program Name box on the main form
      ENTRY_REQUIREMENTS_CHAR_LIMIT = 60
      TMP_DIR = 'tmp/pdfs'
      FORM_CLASS = PdfFill::Forms::Va220976

      def initialize(form_data, main_form_filler, file_name_suffix = SecureRandom.hex)
        @form_data = form_data
        @main_form_filler = main_form_filler
        @file_name_suffix = file_name_suffix
      end

      def process
        FileUtils.mkdir_p(TMP_DIR)
        merged_form_data = FORM_CLASS.new(@form_data).merge_fields
        hash_converter = HashConverter.new(FORM_CLASS.date_strftime, ExtrasGenerator.new)

        programs = merged_form_data['programs'] || []
        branches = merged_form_data['branches'] || []
        faculty = merged_form_data['faculty'] || []

        if programs.size <= DEFAULT_PROGRAMS_LIMIT &&
           branches.size <= DEFAULT_BRANCHES_LIMIT &&
           faculty.size <= DEFAULT_FACULTY_LIMIT &&
           programs.none? { |program_data| entry_requirements_overflow?(program_data) }
          generate_default_form(merged_form_data, hash_converter)
        else
          generate_extended_form(merged_form_data, hash_converter)
        end
      end

      private

      def generate_default_form(merged_form_data, hash_converter)
        pdf_data_hash = hash_converter.transform_data(form_data: merged_form_data, pdftk_keys: FORM_CLASS::KEY)

        file_path = File.join(TMP_DIR, "22-0976_#{@file_name_suffix}.pdf")
        PDF_FORMS.fill_form(DEFAULT_TEMPLATE_PATH, file_path, pdf_data_hash, flatten: Rails.env.production?)
        combine_extras(file_path, hash_converter.extras_generator, FORM_CLASS)
      end

      def generate_extended_form(merged_form_data, hash_converter)
        # extract extra records that don't fit on pdf for later processing

        extra_programs = extract_extra_from_array(merged_form_data['programs'] || [],
                                                  DEFAULT_PROGRAMS_LIMIT)
        extra_branches = extract_extra_from_array(merged_form_data['branches'] || [],
                                                  DEFAULT_BRANCHES_LIMIT)
        extra_faculty = extract_extra_from_array(merged_form_data['faculty'] || [],
                                                 DEFAULT_FACULTY_LIMIT)

        # of the programs that remain on the pdf (<= DEFAULT_PROGRAMS_LIMIT), any whose
        # entry requirements text is too long are pulled out to the overflow page in full
        entry_requirements_overflow = extract_entry_requirements_overflow(merged_form_data['programs'] || [])
        additional_programs = extra_programs + entry_requirements_overflow

        # convert data that will fit naturally onto the pdf
        pdf_data_hash = hash_converter.transform_data(form_data: merged_form_data, pdftk_keys: FORM_CLASS::KEY)

        add_extras(hash_converter, additional_programs, :program_to_text, 0, 'Additional Programs')
        add_extras(hash_converter, extra_branches, :branch_to_text, additional_programs.size,
                   'Additional Branches')
        add_extras(hash_converter, extra_faculty, :faculty_to_text,
                   additional_programs.size + extra_branches.size, 'Additional Officials and Faculty')

        # fill in pdf and append extra pages
        file_path = File.join(TMP_DIR, "22-0976_#{@file_name_suffix}.pdf")
        PDF_FORMS.fill_form(DEFAULT_TEMPLATE_PATH, file_path, pdf_data_hash, flatten: Rails.env.production?)
        combine_extras(file_path, hash_converter.extras_generator, FORM_CLASS)
      end

      def extract_extra_from_array(arr, count)
        extra = arr[count..] || []
        arr.pop(extra.size)
        extra
      end

      # Pulls any program whose entryRequirements text exceeds ENTRY_REQUIREMENTS_CHAR_LIMIT
      # out of the visible programs array (in full, for later rendering on the overflow page),
      # replacing it in place with just a 'See Additional Page' Program Name so its position
      # in the pdf's program list is preserved.
      def extract_entry_requirements_overflow(programs)
        programs.each_with_object([]) do |program_data, overflow|
          next unless entry_requirements_overflow?(program_data)

          overflow << program_data.dup
          program_data.clear
          program_data['programName'] = 'See Additional Page'
        end
      end

      def entry_requirements_overflow?(program_data)
        entry_requirements = program_data['entryRequirements']
        entry_requirements.present? && entry_requirements.size > ENTRY_REQUIREMENTS_CHAR_LIMIT
      end

      def add_extras(converter, arr, to_text_method, start_i, label)
        arr.each_with_index do |data, i|
          converter.extras_generator.add_text(send(to_text_method, data), {
                                                question_num: start_i + i + 1,
                                                question_text: label
                                              })
        end
      end

      def program_to_text(program_data)
        <<~TEXT
          Name: #{program_data['programName']}
          Total Length: #{program_data['totalProgramLength']}
          Number of Weeks per Semester: #{program_data['weeksPerTerm']}
          Entry Requirements: #{program_data['entryRequirements']}
          Number of Credit Hours: #{program_data['creditHours']}
        TEXT
      end

      def branch_to_text(branch_data)
        <<~TEXT
          Name: #{branch_data['name']}
          Address: #{branch_data['address']}
        TEXT
      end

      def faculty_to_text(faculty_data)
        <<~TEXT
          Name: #{faculty_data['name']}
          Title: #{faculty_data['title']}
        TEXT
      end
    end
  end
end
