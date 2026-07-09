# frozen_string_literal: true

module IvcChampva
  module FormMappers
    class VHA107959cRev2025
      include Base

      def initialize(data)
        @data = data
      end

      def mapped_fields # rubocop:disable Metrics/MethodLength
        gender_raw = @data['applicant_gender']
        gender_val = gender_raw.is_a?(Hash) ? gender_raw['gender'] : gender_raw
        medicare = @data['medicare']
        plan_type = medicare&.dig(0, 'medicare_plan_type')
        med = medicare.present?
        primary_type = @data['applicant_primary_insurance_type']
        secondary_type = @data['applicant_secondary_insurance_type']
        has_primary = @data['applicant_primary_provider'].present?
        has_secondary = @data['applicant_secondary_provider'].present?

        pri_employer = has_primary ? radio(truthy?(@data['applicant_primary_through_employer'])) : nil
        sec_employer = has_secondary ? radio(truthy?(@data['applicant_secondary_through_employer'])) : nil

        {
          'applicant_last_name' => name_with_suffix(@data.dig('applicant_name', 'last'),
                                                    @data.dig('applicant_name', 'suffix')),
          'applicant_first_name' => @data.dig('applicant_name', 'first'),
          'applicant_middle_initial' => middle_initial(@data.dig('applicant_name', 'middle')),
          'applicant_ssn' => @data['applicant_ssn'],
          'applicant_street_address' => @data.dig('applicant_address', 'street_combined'),
          'applicant_city' => @data.dig('applicant_address', 'city'),
          'applicant_state' => @data.dig('applicant_address', 'state'),
          'applicant_zip' => @data.dig('applicant_address', 'postal_code'),
          'applicant_country' => @data.dig('applicant_address', 'country'),
          'applicant_email' => @data['applicant_email_address'],
          'applicant_phone' => @data['applicant_phone'],
          'new_address_radio' => radio(@data['applicant_new_address'] == 'no'),
          'applicant_gender_radio' => radio(gender_val == 'male'),
          'medicare_part_a_radio' => med ? radio(%w[a ab c].include?(plan_type)) : nil,
          'medicare_part_a_effective_date' => @data.dig('medicare', 0, 'medicare_part_a_effective_date'),
          'medicare_part_b_radio' => med ? radio(%w[b ab c].include?(plan_type)) : nil,
          'medicare_part_b_effective_date' => @data.dig('medicare', 0, 'medicare_part_b_effective_date'),
          'medicare_part_c_radio' => med ? radio(plan_type == 'c') : nil,
          'medicare_part_c_carrier' => @data.dig('medicare', 0, 'medicare_part_c_carrier'),
          'medicare_part_c_effective_date' => @data.dig('medicare', 0, 'medicare_part_c_effective_date'),
          'medicare_part_d_radio' => med ? radio(truthy?(medicare.dig(0, 'has_medicare_part_d'))) : nil,
          'medicare_number' => @data.dig('medicare', 0, 'medicare_number'),
          'medicare_part_d_effective_date' => @data.dig('medicare', 0, 'medicare_part_d_effective_date'),
          'medicare_part_d_termination_date' => @data.dig('medicare', 0, 'medicare_part_d_termination_date'),
          'has_other_insurance_radio' => radio(@data['applicant_primary_provider'].nil?),
          'primary_provider' => @data['applicant_primary_provider'],
          'primary_effective_date' => @data['applicant_primary_effective_date'],
          'primary_expiration_date' => @data['applicant_primary_expiration_date'],
          'primary_through_employer_radio' => pri_employer,
          'primary_eob_radio' => eob_radio(@data['applicant_primary_eob']),
          'primary_insurance_hmo' => primary_type == 'hmo' ? 1 : 'Off',
          'primary_insurance_ppo' => primary_type == 'ppo' ? 2 : 'Off',
          'primary_insurance_medicaid' => primary_type == 'medicaid' ? 3 : 'Off',
          'primary_insurance_medigap' => primary_type == 'medigap' ? 4 : 'Off',
          'primary_medigap_plan' => @data['primary_medigap_plan'],
          'primary_insurance_other' => primary_type == 'other' ? 6 : 'Off',
          'primary_additional_comments' => @data['primary_additional_comments'],
          'secondary_provider' => @data['applicant_secondary_provider'],
          'secondary_effective_date' => @data['applicant_secondary_effective_date'],
          'secondary_expiration_date' => @data['applicant_secondary_expiration_date'],
          'secondary_through_employer_radio' => sec_employer,
          'secondary_eob_radio' => eob_radio(@data['applicant_secondary_eob']),
          'secondary_insurance_hmo' => secondary_type == 'hmo' ? 1 : 'Off',
          'secondary_insurance_ppo' => secondary_type == 'ppo' ? 2 : 'Off',
          'secondary_insurance_medicaid' => secondary_type == 'medicaid' ? 3 : 'Off',
          'secondary_insurance_medigap' => secondary_type == 'medigap' ? 4 : 'Off',
          'secondary_medigap_plan' => @data['secondary_medigap_plan'],
          'secondary_insurance_other' => secondary_type == 'other' ? 6 : 'Off',
          'secondary_additional_comments' => @data['secondary_additional_comments'],
          'statement_of_truth_signature' => @data['statement_of_truth_signature'],
          'certification_date' => @data['certification_date']
        }
      end

      private

      def radio(condition)
        condition ? 0 : 1
      end

      def eob_radio(val)
        val.nil? ? 'Off' : radio(truthy?(val))
      end
    end
  end
end
