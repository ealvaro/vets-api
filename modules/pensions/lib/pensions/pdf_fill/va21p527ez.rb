# frozen_string_literal: true

require 'pdf_fill/forms/form_base'

# V1: Sections
require_relative 'sections/section_01'
require_relative 'sections/section_02'
require_relative 'sections/section_03'
require_relative 'sections/section_04'
require_relative 'sections/section_05'
require_relative 'sections/section_06'
require_relative 'sections/section_07'
require_relative 'sections/section_08'
require_relative 'sections/section_09'
require_relative 'sections/section_10'
require_relative 'sections/section_11'
require_relative 'sections/section_12'

# V2: Sections
require_relative 'sections/section_01_v2'
require_relative 'sections/section_02_v2'
require_relative 'sections/section_03_v2'
require_relative 'sections/section_04_v2'
require_relative 'sections/section_05_v2'
require_relative 'sections/section_06_v2'
require_relative 'sections/section_07_v2'
require_relative 'sections/section_08_v2'
require_relative 'sections/section_09_v2'
require_relative 'sections/section_10_v2'
require_relative 'sections/section_11_v2'
require_relative 'sections/section_12_v2'

module Pensions
  module PdfFill
    # The Va21p527ez Form
    class Va21p527ez < ::PdfFill::Forms::FormBase
      # The Form ID
      FORM_ID = Pensions::FORM_ID

      # TODO: Enable TEMPLATE constant after version migration complete
      #
      #   The PDF Template
      #   TEMPLATE = "#{Pensions::MODULE_PATH}/lib/pensions/pdf_fill/pdfs/21P-527EZ.pdf".freeze

      # TODO: Enable START_PAGE constant after version migration complete
      #
      #   START_PAGE = 18

      # V1: Overflow start page for
      START_PAGE_V1 = 16
      # V2: Overflow start page for
      START_PAGE_V2 = 18

      # Default label column width (points) for redesigned extras in this form
      DEFAULT_LABEL_WIDTH = 130

      # V1: Map question numbers to descriptive titles for overflow attachments
      QUESTION_KEY_V1 = [
        { question_number: '1', question_text: "Veteran's Identification Information" },
        { question_number: '2', question_text: "Veteran's Contact Information" },
        { question_number: '3', question_text: "Veteran's Service Information" },
        { question_number: '4', question_text: 'VA Medical Centers' },
        { question_number: '4g', question_text: 'Federal Medical Facilities' },
        { question_number: '5', question_text: 'Employment History' },
        { question_number: '6', question_text: 'Marital Status' },
        { question_number: '7', question_text: 'Prior Marital History' },
        { question_number: '7b', question_text: 'Spouse\'s Prior Marital History' },
        { question_number: '8', question_text: 'Dependent Children' },
        { question_number: '9', question_text: 'Income and Assets' },
        { question_number: '10', question_text: 'Care Expenses' },
        { question_number: '10b', question_text: 'Medical Expenses' },
        { question_number: '11', question_text: 'Direct Deposit Information' },
        { question_number: '12', question_text: 'Claim Certification and Signature' }
      ].freeze

      # V2: Map question numbers to descriptive titles for overflow attachments
      QUESTION_KEY_V2 = [
        { question_number: '1', question_text: "Veteran's Identification Information" },
        { question_number: '2', question_text: "Veteran's Contact Information" },
        { question_number: '3', question_text: "Veteran's Service Information" },
        { question_number: '3f', question_text: 'Place of Your Last Separation' },
        { question_number: '4', question_text: 'VA Medical Centers' },
        { question_number: '4g', question_text: 'Federal Medical Facilities' },
        { question_number: '5', question_text: 'Employment History' },
        { question_number: '6', question_text: 'Marital Status' },
        { question_number: '7', question_text: 'Prior Marital History' },
        { question_number: '7b', question_text: 'Spouse\'s Prior Marital History' },
        { question_number: '8', question_text: 'Dependent Children' },
        { question_number: '9', question_text: 'Income and Assets' },
        { question_number: '10', question_text: 'Care Expenses' },
        { question_number: '10b', question_text: 'Medical Expenses' },
        { question_number: '11', question_text: 'Direct Deposit Information' },
        { question_number: '12', question_text: 'Claim Certification and Signature' }
      ].freeze

      # Sections grouping question numbers for overflow pages
      SECTIONS = [
        { label: 'Section I: Veteran\'s Identification Information', question_nums: ['1'] },
        { label: 'Section II: Veteran\'s Contact Information', question_nums: ['2'] },
        { label: 'Section III: Veteran\'s Service Information', question_nums: ['3'] },
        { label: 'Section IV: Pension Information', question_nums: ['4'] },
        { label: 'Section V: Employment History', question_nums: ['5'] },
        { label: 'Section VI: Marital Status', question_nums: ['6'] },
        { label: 'Section VII: Prior Marital History', question_nums: ['7'] },
        { label: 'Section VIII: Dependent Children', question_nums: ['8'] },
        { label: 'Section IX: Income and Assets', question_nums: ['9'] },
        { label: 'Section X: Care/Medical Expenses', question_nums: ['10'] },
        { label: 'Section XI: Direct Deposit Information', question_nums: ['11'] },
        { label: 'Section XII: Claim Certification and Signature', question_nums: ['12'] }
      ].freeze

      # V1: The list of section classes for form expansion and key building
      SECTION_CLASSES_V1 = [
        Section1, Section2, Section3, Section4, Section5, Section6,
        Section7, Section8, Section9, Section10, Section11, Section12
      ].freeze

      # V2: The list of section classes for form expansion and key building
      SECTION_CLASSES_V2 = [
        Section1V2, Section2V2, Section3V2, Section4V2, Section5V2, Section6V2,
        Section7V2, Section8V2, Section9V2, Section10V2, Section11V2, Section12V2
      ].freeze

      # @note Enable conventional KEY constant after version migration complete
      #
      #   Build the full key by merging in section keys
      #   key = {}
      #
      #   form configuration hash
      #   KEY = key.freeze

      ##
      # Return the dynamic PDF field mapping key based on the current version.
      # Builds the key by merging all section KEY constants.
      #
      # TODO: Remove after version migration complete
      #
      # @return [Hash] The PDF field mapping for the current version
      def key
        @key ||= begin
          k = {}
          section_classes.each { |section| k.merge!(section::KEY) }
          k.freeze
        end
      end

      ##
      # Merge all the key data together
      #
      def merge_fields(_options = {})
        section_classes.each { |section| section.new.expand(@form_data) }

        @form_data
      end

      ##
      # Get start page depending on which version PDF is in use
      #
      # @see PdfFill::Fill#make_hash_converter
      #
      # TODO: Remove after version migration complete
      #
      # @return [Integer]
      def start_page
        Pensions.use_v2? ? START_PAGE_V2 : START_PAGE_V1
      end

      ##
      # Get question key depending on which version PDF is in use
      #
      # TODO: Remove after version migration complete
      #
      # @return [Array<Hash>]
      def question_key
        Pensions.use_v2? ? QUESTION_KEY_V2 : QUESTION_KEY_V1
      end

      ##
      # Get section classes depending on which version PDF is in use
      #
      # TODO: Remove after version migration complete
      #
      # @return [Array<Hash>]
      def section_classes
        Pensions.use_v2? ? SECTION_CLASSES_V2 : SECTION_CLASSES_V1
      end

      ##
      # Return the PDF template path. Uses Pensions module's dynamic path resolution.
      #
      # TODO: Update after version migration complete
      #
      # @return [String] Path to the PDF template file
      def template
        Pensions.pdf_path
      end
    end
  end
end
