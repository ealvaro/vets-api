# frozen_string_literal: true

module IvcChampva
  module FormMappers
    class VHA107959a2027
      include Base

      def initialize(data)
        @data = data
      end

      def mapped_fields # rubocop:disable Metrics/MethodLength
        {
          'applicant_middle_initial' => middle_initial(@data.dig('applicant_name', 'middle')),
          'applicant_first_name' => @data.dig('applicant_name', 'first'),
          'applicant_last_name' => @data.dig('applicant_name', 'last'),
          'applicant_member_number' => @data['applicant_member_number'],
          'applicant_zip' => @data.dig('applicant_address', 'postal_code'),
          'applicant_state' => @data.dig('applicant_address', 'state'),
          'applicant_city' => @data.dig('applicant_address', 'city'),
          'applicant_street_address' => @data.dig('applicant_address', 'street_combined'),
          'applicant_phone' => @data['applicant_phone'],
          'applicant_email' => @data['applicant_email'],
          'applicant_dob' => @data['applicant_dob'],
          'new_address_radio' => @data['applicant_new_address'] == 'no' ? 0 : 1,
          'sponsor_last_name' => @data.dig('sponsor_name', 'last'),
          'sponsor_first_name' => @data.dig('sponsor_name', 'first'),
          'sponsor_middle_initial' => middle_initial(@data.dig('sponsor_name', 'middle')),
          'has_ohi_radio' => ohi_label,
          'policy_type_radio' => policy_type_label,
          'policy_other_type' => @data.dig('policies', 0, 'other_type'),
          'policy_1_name' => @data.dig('policies', 0, 'name'),
          'policy_1_phone' => @data.dig('policies', 0, 'provider_phone'),
          'policy_1_number' => @data.dig('policies', 0, 'policy_num'),
          'policy_1_effective_date' => @data.dig('policies', 0, 'effective_date'),
          'policy_1_expiration_date' => @data.dig('policies', 0, 'expiration_date'),
          'policy_2_name' => @data.dig('policies', 1, 'name'),
          'policy_2_number' => @data.dig('policies', 1, 'policy_num'),
          'policy_2_phone' => @data.dig('policies', 1, 'provider_phone'),
          'policy_2_effective_date' => @data.dig('policies', 1, 'effective_date'),
          'policy_2_expiration_date' => @data.dig('policies', 1, 'expiration_date'),
          'claim_is_work_related_radio' => truthy?(@data.dig('claims', 0, 'claim_is_work_related')) ? 'Yes' : 'No',
          'claim_is_auto_related_radio' => truthy?(@data.dig('claims', 0, 'claim_is_auto_related')) ? 'Yes' : 'No',
          'certifier_middle_initial' => middle_initial(@data.dig('certifier_name', 'middle')),
          'certifier_first_name' => @data.dig('certifier_name', 'first'),
          'certifier_last_name' => @data.dig('certifier_name', 'last'),
          'certifier_relationship' => certifier_relationship_value,
          'certifier_phone' => @data['certifier_phone'],
          'certifier_zip' => @data.dig('certifier_address', 'postal_code'),
          'certifier_state' => @data.dig('certifier_address', 'state'),
          'certifier_city' => @data.dig('certifier_address', 'city'),
          'certifier_street_address' => @data.dig('certifier_address', 'street_combined'),
          'certifier_email' => @data['certifier_email'],
          'certification_date' => @data['certification_date'],
          'statement_of_truth_signature' => @data['statement_of_truth_signature']
        }
      end

      private

      def ohi_label
        if truthy?(@data['has_ohi'])
          'Yes (check type and provide coverage information below)'
        else
          'No (proceed to Section III)'
        end
      end

      def policy_type_label
        type = @data.dig('policies', 0, 'type')
        case type
        when 'group' then 'Employer sponsored (group) '
        when 'nonGroup' then 'Private (non group) '
        when 'medicare' then 'Medicare (Part A or B) '
        when 'other' then 'Other (Specify):'
        else 'Off'
        end
      end

      def certifier_relationship_value
        rel = @data['certifier_relationship']
        rel == 'other' ? @data['certifier_other_relationship'] : rel
      end
    end
  end
end
