# frozen_string_literal: true

require 'mms/data_formatting'

module SurvivorsBenefits
  module StructuredData
    module V2022
      class StructuredDataService
        include SurvivorsBenefits::StructuredData::V2022::Section01
        include SurvivorsBenefits::StructuredData::V2022::Section02
        include SurvivorsBenefits::StructuredData::V2022::Section03
        include SurvivorsBenefits::StructuredData::V2022::Section04
        include SurvivorsBenefits::StructuredData::V2022::Section05
        include SurvivorsBenefits::StructuredData::V2022::Section06
        include SurvivorsBenefits::StructuredData::V2022::Section07
        include SurvivorsBenefits::StructuredData::V2022::Section08
        include SurvivorsBenefits::StructuredData::V2022::Section09
        include SurvivorsBenefits::StructuredData::V2022::Section10
        include SurvivorsBenefits::StructuredData::V2022::Section11
        include SurvivorsBenefits::StructuredData::V2022::Section12
        include Mms::DataFormatting

        attr_reader :form
        attr_accessor :fields

        FIELDS_PATH = Rails.root.join(
          'modules',
          'survivors_benefits',
          'app',
          'services',
          'survivors_benefits',
          'structured_data',
          'V2022',
          'fields.yaml'
        ).freeze

        IRREGULAR_FIELD_TRANSFORMS = {
          'CB_CL_MARR2_ENDED_OTHEREXPLAIN' => 'CL_MARR2_ENDED_OTHEREXPLAIN',
          'AMNT_YOU_PAY_1' => 'AMNT_YOU_PAY1',
          'MONTHLY_GROSS_1' => 'MONTHLY_GROSS_1_'
        }.freeze

        AMNT_YOU_PAY_COUNT = 3
        MEDAMNT_YOU_PAY_COUNT = 6

        def initialize(form)
          @form = form
          @fields = YAML.load_file(FIELDS_PATH)
        end

        def build_structured_data
          build_section1
          build_section2
          build_section3
          build_section4
          build_section5
          build_section6
          build_section7
          build_section8
          build_section9
          build_section10
          build_section11(form['bankAccount'])
          build_section12
          fill_veteran_ssn_reference_fields
          add_amounts_with_separation
          transform_booleans(fields)
          transform_nils_to_empty_strings(fields)
          transform_irregular_fields
          fields
        end

        ##
        # Build the name fields from the form data.
        # used by Section01 and Section02
        # @param name [Hash]
        # @param individual [String] - The prefix for the field keys (e.g., "VETERAN", "CLAIMANT")
        def merge_name_fields(name, individual)
          if name && %w[VETERAN CLAIMANT].include?(individual)
            name = build_name(name)
            fields.merge!(
              {
                "#{individual}_NAME" => name[:full],
                "#{individual}_FIRST_NAME" => name[:first],
                "#{individual}_MIDDLE_INITIAL" => name[:middle_initial],
                "#{individual}_LAST_NAME" => name[:last]
              }
            )
          end
        end

        def fill_veteran_ssn_reference_fields
          ssn = form['veteranSocialSecurityNumber']
          (1..9).each { |i| fields["VETERAN_SSN_#{i}"] = ssn }
        end

        def transform_irregular_fields
          fields.transform_keys!(IRREGULAR_FIELD_TRANSFORMS)
        end

        def add_amounts_with_separation
          (1..AMNT_YOU_PAY_COUNT).each do |i|
            fields["AMNT_YOU_PAY_#{i}_WITH_SEPARATION"] = fields["AMNT_YOU_PAY_#{i}"]
          end

          (1..MEDAMNT_YOU_PAY_COUNT).each do |i|
            fields["MEDAMNT_YOU_PAY#{i}_WITH_SEPARATION"] = fields["MEDAMNT_YOU_PAY#{i}"]
          end
        end
      end
    end
  end
end
